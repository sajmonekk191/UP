import Foundation

/// Build steps, situational items, lane matchup and enemy threats for the match overview.
struct MatchInsights {
    struct BuildStep: Identifiable, Hashable {
        enum State { case owned, next, later }
        var itemId: Int
        var state: State
        var id: Int { itemId }
    }

    struct Suggestion: Identifiable, Hashable {
        var itemId: Int
        var reason: String
        var id: String { "\(itemId)-\(reason)" }
    }

    struct Threat: Identifiable, Hashable {
        var championId: Int?
        var name: String
        var detail: String
        var id: String { name }
    }

    enum DamageProfile { case magic, physical, tank }

    var steps: [BuildStep] = []
    var skillPriority: [String] = []
    var suggestions: [Suggestion] = []
    var threats: [Threat] = []
    var opponentId: Int?
    var matchupWinRate: Double?
    var matchupTip: String?
    var enemyMagicShare = 0.0
    var profile: DamageProfile = .physical

    static let healers: Set<String> = ["Aatrox", "Soraka", "Vladimir", "Sylas", "Warwick", "DrMundo", "Yuumi", "Nami", "Sona",
                                       "Swain", "Fiddlesticks", "Briar", "Olaf", "Illaoi", "Maokai", "Senna", "Seraphine", "Kayn", "Nasus"]
    static let shielders: Set<String> = ["Lulu", "Janna", "Karma", "Sett", "Seraphine", "Renata", "Milio", "Lux", "Rakan", "Orianna", "Ivern"]

    @MainActor
    init(live: LiveGameSnapshot, hud: HUDState, data: GameData) {
        guard let me = live.me else { return }
        let owned = Set(me.items.map(\.itemID))
        let enemies = live.players.filter { $0.team != live.myTeam }
        let myDetail = hud.myChampionId.flatMap { data.details[$0] }
        profile = (myDetail?.roles ?? []).contains("tank") ? .tank
            : myDetail?.tacticalInfo?.damageType == "kMagic" ? .magic : .physical

        if let build = hud.myBuild {
            var ordered: [Int] = []
            for id in (build.boots.first?.ids ?? []) + (build.coreItems.first?.ids ?? []) + build.lastItems.prefix(3).flatMap(\.ids)
            where !ordered.contains(id) { ordered.append(id) }
            var nextAssigned = false
            steps = ordered.map { id in
                if owned.contains(id) { return BuildStep(itemId: id, state: .owned) }
                defer { nextAssigned = true }
                return BuildStep(itemId: id, state: nextAssigned ? .later : .next)
            }
            skillPriority = build.skillOrder?.priority ?? []

            let opponent = enemies.first { $0.position == me.position && me.position != nil && me.position != "" }
            if let opponent, let id = data.champion(named: opponent.championName)?.id {
                opponentId = id
                matchupWinRate = build.counters.first { $0.championId == id }?.winRate
                let name = data.championName(id)
                if let wr = matchupWinRate {
                    matchupTip = wr >= 0.52 ? tr("You're favoured vs %@: trade aggressively and look for kills.", name)
                        : wr <= 0.48 ? tr("%@ counters you: farm safely, avoid long trades and wait for your jungler.", name)
                        : tr("Even matchup vs %@: whoever uses their power spikes better wins.", name)
                }
            }
        }

        let enemyDetails = enemies.compactMap { data.champion(named: $0.championName).flatMap { data.details[$0.id] } }
        let magic = enemyDetails.filter { $0.tacticalInfo?.damageType == "kMagic" }.count
        enemyMagicShare = enemyDetails.isEmpty ? 0 : Double(magic) / Double(enemyDetails.count)
        let cc = enemyDetails.map { $0.playstyleInfo?.crowdControl ?? 0 }.reduce(0, +)
        let tanks = enemyDetails.filter { ($0.playstyleInfo?.durability ?? 0) >= 3 }.count
        let healerNames = enemies.map(\.championName).filter(Self.healers.contains)
        let shieldNames = enemies.map(\.championName).filter(Self.shielders.contains)

        func add(_ ids: [Int], _ reason: String) {
            guard let id = ids.first(where: { data.items[$0] != nil && !owned.contains($0) }) else { return }
            suggestions.append(Suggestion(itemId: id, reason: reason))
        }
        if !healerNames.isEmpty {
            let who = healerNames.prefix(2).map { data.champion(named: $0)?.name ?? $0 }.joined(separator: ", ")
            switch profile {
            case .magic: add([3165, 3916], tr("Anti-heal vs %@", who))
            case .physical: add([3033, 3123], tr("Anti-heal vs %@", who))
            case .tank: add([3075, 3076], tr("Anti-heal vs %@", who))
            }
        }
        if enemyMagicShare >= 0.6 {
            switch profile {
            case .magic: add([3102], tr("Magic resist vs an AP-heavy team"))
            case .physical: add([3156, 3091], tr("Magic resist vs an AP-heavy team"))
            case .tank: add([4401, 2504, 3065], tr("Magic resist vs an AP-heavy team"))
            }
        } else if enemyMagicShare <= 0.4, !enemyDetails.isEmpty {
            switch profile {
            case .magic: add([3157], tr("Armor and stasis vs an AD-heavy team"))
            case .physical: add([6333, 3026], tr("Survive an AD-heavy team"))
            case .tank: add([3143, 3110, 3075], tr("Armor vs an AD-heavy team"))
            }
        }
        if cc >= 11 {
            add([3111], tr("Tenacity vs heavy crowd control"))
            if profile == .physical { add([3139, 3140], tr("Cleanse their key crowd control")) }
        }
        if tanks >= 2, profile != .tank {
            add(profile == .magic ? [3135, 6653] : [3036, 3071, 6694], tr("Penetration vs %d tanks", tanks))
        }
        if !shieldNames.isEmpty, profile == .physical {
            add([6695], tr("Cuts shields from %@", data.champion(named: shieldNames[0])?.name ?? shieldNames[0]))
        }

        threats = enemies.compactMap { enemy -> Threat? in
            let id = data.champion(named: enemy.championName)?.id
            let name = data.championName(id)
            let lead = enemy.scores.kills - enemy.scores.deaths
            if lead >= 3 { return Threat(championId: id, name: name, detail: tr("Fed %d/%d/%d: don't fight them alone", enemy.scores.kills, enemy.scores.deaths, enemy.scores.assists)) }
            if enemy.level >= (me.level + 2) { return Threat(championId: id, name: name, detail: tr("%d levels ahead of you", enemy.level - me.level)) }
            let counters = enemy.items.map(\.itemID).filter { LiveGameAnalyzer.counterItems[$0] != nil }
            if let item = counters.first { return Threat(championId: id, name: name, detail: tr("Has %@", data.items[item]?.name ?? "")) }
            return nil
        }
    }
}

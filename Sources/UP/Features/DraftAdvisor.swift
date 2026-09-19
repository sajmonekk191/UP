import Foundation

struct Reason: Hashable, Sendable, Identifiable {
    var text: String
    var positive: Bool
    var id: String { text }
}

struct PickSuggestion: Identifiable, Sendable {
    var championId: Int
    var score: Int
    var winRate: Double
    var tier: Int
    var matchups: [(enemyId: Int, winRate: Double)]
    var personalGames: Int
    var personalWinRate: Double?
    var masteryPoints: Int
    var reasons: [Reason]
    var id: Int { championId }
}

struct BanSuggestion: Identifiable, Sendable {
    var championId: Int
    var winRate: Double
    var banRate: Double
    var reason: String
    var id: Int { championId }
}

/// Damage profile and role strength of one team's revealed champions.
struct TeamComposition: Sendable {
    var champions: [Int] = []
    var physical = 0, magic = 0, mixed = 0
    var frontline = 0.0, crowdControl = 0.0, mobility = 0.0, damage = 0.0
    var melee = 0, ranged = 0

    var count: Int { champions.count }
    var physicalShare: Double { count == 0 ? 0 : (Double(physical) + Double(mixed) / 2) / Double(count) }
    var magicShare: Double { count == 0 ? 0 : (Double(magic) + Double(mixed) / 2) / Double(count) }

    init() {}

    init(champions: [Int], details: [Int: ChampionDetail]) {
        self.champions = champions
        for id in champions {
            guard let d = details[id] else { continue }
            switch d.tacticalInfo?.damageType {
            case "kMagic": magic += 1
            case "kPhysical": physical += 1
            default: mixed += 1
            }
            if d.tacticalInfo?.attackType == "melee" { melee += 1 } else { ranged += 1 }
            frontline += Double(d.playstyleInfo?.durability ?? 0)
            crowdControl += Double(d.playstyleInfo?.crowdControl ?? 0)
            mobility += Double(d.playstyleInfo?.mobility ?? 0)
            damage += Double(d.playstyleInfo?.damage ?? 0)
        }
    }
}

struct Tip: Identifiable, Hashable, Sendable {
    enum Tone: Sendable { case good, warning, info }
    var symbol: String
    var text: String
    var tone: Tone
    var id: String { text }
}

/// Champ-select strategy: pick and ban suggestions, compositions and the build for the focused champion.
@MainActor
@Observable
final class DraftAdvisor {
    private(set) var lane: Lane?
    private(set) var suggestions: [PickSuggestion] = []
    private(set) var bans: [BanSuggestion] = []
    private(set) var loadingSuggestions = false
    private(set) var ally = TeamComposition()
    private(set) var enemy = TeamComposition()
    private(set) var compTips: [Tip] = []

    private(set) var focusChampion: Int?
    private(set) var focusLocked = false
    private(set) var builds: [EloTier: ChampionBuild] = [:]
    private(set) var riotRunes: [RuneSetup] = []
    private(set) var loadingFocus = false
    private(set) var laneOpponent: Int?
    private(set) var gamePlan: [Tip] = []

    var laneOverride: Lane? { didSet { if oldValue != laneOverride { suggestionKey = "" } } }

    private var owned: Set<Int> = []
    private var suggestionKey = ""
    private var focusKey = ""
    private var compKey = ""
    private var suggestionTask: Task<Void, Never>?
    private var focusTask: Task<Void, Never>?

    var build: ChampionBuild? { builds[.emeraldPlus] }

    func reset() {
        suggestions = []; bans = []; builds = [:]; riotRunes = []; gamePlan = []; compTips = []
        focusChampion = nil; focusLocked = false; laneOpponent = nil; laneOverride = nil
        suggestionKey = ""; focusKey = ""; compKey = ""; owned = []
        ally = TeamComposition(); enemy = TeamComposition()
    }

    /// Recomputes whatever the new session state invalidates.
    func update(_ session: ChampSelectSession, model: AppModel) {
        let me = session.me
        let isAram = model.queueMode == .aram
        let assigned = Lane(clientPosition: me?.assignedPosition)
        lane = isAram ? nil : (laneOverride ?? assigned ?? model.myProfile?.roleShares.first?.lane ?? .middle)

        let actions: [ChampSelectAction] = (session.actions ?? []).flatMap { $0 }
        let bans: [ChampSelectAction] = actions.filter { $0.type == "ban" && $0.completed == true }
        let banned: Set<Int> = Set(bans.compactMap(\.championId))
        let allyIds = session.myTeam.map(\.displayedChampionId).filter { $0 > 0 }
        let enemyIds = (session.theirTeam ?? []).map(\.displayedChampionId).filter { $0 > 0 }
        let taken = banned.union(allyIds).union(enemyIds)

        let newCompKey = "\(allyIds)|\(enemyIds)"
        if newCompKey != compKey {
            compKey = newCompKey
            Task { await refreshComps(allyIds: allyIds, enemyIds: enemyIds, model: model) }
        }

        let newSuggestionKey = "\(lane?.rawValue ?? "aram")|\(enemyIds.sorted())|\(taken.sorted())|\(allyIds.filter { $0 != me?.displayedChampionId }.sorted())"
        if !isAram, newSuggestionKey != suggestionKey {
            suggestionKey = newSuggestionKey
            suggestionTask?.cancel()
            suggestionTask = Task { await refreshSuggestions(enemyIds: enemyIds, taken: taken, allyIds: allyIds, model: model) }
        }

        let champion = me?.displayedChampionId ?? 0
        let myCell = session.localPlayerCellId
        let pickedByMe: Bool = actions.contains { (a: ChampSelectAction) -> Bool in a.actorCellId == myCell && a.type == "pick" && a.completed == true }
        let locked = pickedByMe || (isAram && champion > 0)
        let newFocusKey = "\(champion)|\(locked)|\(lane?.rawValue ?? "-")|\(enemyIds.sorted())"
        if newFocusKey != focusKey {
            focusKey = newFocusKey
            focusChampion = champion > 0 ? champion : nil
            focusLocked = locked
            focusTask?.cancel()
            focusTask = Task { await refreshFocus(champion: champion, enemyIds: enemyIds, model: model) }
        }
    }

    // MARK: Suggestions

    private func refreshSuggestions(enemyIds: [Int], taken: Set<Int>, allyIds: [Int], model: AppModel) async {
        guard let lane, let client = model.client else { return }
        loadingSuggestions = true
        defer { loadingSuggestions = false }

        if owned.isEmpty, let data = try? await client.request("GET", "/lol-champions/v1/owned-champions-minimal"),
           let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            owned = Set(list.compactMap { champ in
                let ownership = champ["ownership"] as? [String: Any]
                let has = (ownership?["owned"] as? Bool) == true || (champ["freeToPlay"] as? Bool) == true
                return has ? champ["id"] as? Int : nil
            })
        }
        let tierList = (try? await BuildService.tierList()) ?? []
        let laneEntries = tierList.filter { $0.lane == lane }

        var candidates = laneEntries.filter { !taken.contains($0.championId) && (owned.isEmpty || owned.contains($0.championId)) && $0.pickRate > 0.004 }
            .sorted { $0.rank < $1.rank }.prefix(14).map { $0 }
        let comfort = (model.myProfile?.champions ?? []).map(\.championId) + model.myMasteries.prefix(6).map(\.championId)
        for id in comfort where !taken.contains(id) && !candidates.contains(where: { $0.championId == id }) {
            if let entry = laneEntries.first(where: { $0.championId == id }) { candidates.append(entry) }
        }

        let opponent = enemyIds.first { id in tierList.filter { $0.championId == id }.max { $0.play < $1.play }?.lane == lane }
        laneOpponent = opponent

        var results: [PickSuggestion] = []
        await withTaskGroup(of: (TierListEntry, ChampionBuild?).self) { group in
            for entry in candidates {
                group.addTask { (entry, try? await BuildService.opggBuild(championId: entry.championId, lane: lane, mode: .ranked)) }
            }
            for await (entry, build) in group {
                if let build { BuildCacheSnapshot.last[entry.championId] = build }
                _ = await model.gameData.detail(entry.championId, client: client)
                results.append(score(entry, build: build, enemyIds: enemyIds, opponent: opponent, model: model))
            }
        }
        guard !Task.isCancelled else { return }
        suggestions = results.sorted { $0.score > $1.score }

        bans = banSuggestions(laneEntries: laneEntries, taken: taken, model: model)
    }

    private func score(_ entry: TierListEntry, build: ChampionBuild?, enemyIds: [Int], opponent: Int?, model: AppModel) -> PickSuggestion {
        var score = 50.0 + (entry.winRate - 0.5) * 300
        var reasons: [Reason] = []
        if entry.tier <= 1 { score += 4 }
        else if entry.tier == 2 { score += 2 }
        reasons.append(Reason(text: tr("%@ tier · %@ WR", tierName(entry.tier), percent(entry.winRate)), positive: entry.tier <= 2))

        var matchups: [(Int, Double)] = []
        for enemyId in enemyIds {
            guard let m = build?.counters.first(where: { $0.championId == enemyId }) else { continue }
            matchups.append((enemyId, m.winRate))
            let weight = enemyId == opponent ? 2.0 : 0.6
            score += (m.winRate - 0.5) * 200 * weight / Double(max(enemyIds.count, 1)) * 1.5
            let name = model.gameData.championName(enemyId)
            if m.winRate >= 0.52 { reasons.append(Reason(text: tr("Beats %@ (%@)", name, percent(m.winRate, digits: 0)), positive: true)) }
            if m.winRate <= 0.47 { reasons.append(Reason(text: tr("Weak vs %@ (%@)", name, percent(m.winRate, digits: 0)), positive: false)) }
        }

        let record = model.myProfile?.record(for: entry.championId)
        let mastery = model.myMasteries.first { $0.championId == entry.championId }
        let points = mastery?.championPoints ?? 0
        if let record, record.games >= 3 {
            score += (record.winRate - 0.5) * 30 + 3
            reasons.append(Reason(text: tr("Your pick · %d games, %@", record.games, percent(record.winRate, digits: 0)), positive: record.winRate >= 0.5))
        }
        if points >= 100_000 { score += 7; reasons.append(Reason(text: tr("Mastery %@", compact(Double(points))), positive: true)) }
        else if points >= 25_000 { score += 3; reasons.append(Reason(text: tr("Mastery %@", compact(Double(points))), positive: true)) }
        else if points < 3_000 && (record?.games ?? 0) == 0 { score -= 4; reasons.append(Reason(text: tr("New to you"), positive: false)) }

        if let type = model.gameData.details[entry.championId]?.tacticalInfo?.damageType, ally.count >= 2 {
            if type == "kMagic", ally.physicalShare >= 0.75 { score += 4; reasons.append(Reason(text: tr("Adds magic damage your team lacks"), positive: true)) }
            if type == "kPhysical", ally.magicShare >= 0.75 { score += 4; reasons.append(Reason(text: tr("Adds physical damage your team lacks"), positive: true)) }
        }

        return PickSuggestion(championId: entry.championId, score: Int(min(max(score, 0), 99)), winRate: entry.winRate, tier: entry.tier,
                              matchups: matchups, personalGames: record?.games ?? 0, personalWinRate: record?.winRate,
                              masteryPoints: points, reasons: reasons)
    }

    private func banSuggestions(laneEntries: [TierListEntry], taken: Set<Int>, model: AppModel) -> [BanSuggestion] {
        var result: [BanSuggestion] = []
        let topPicks = Set(suggestions.prefix(8).map(\.championId))
        if let best = suggestions.first, let build = BuildCacheSnapshot.last[best.championId] {
            for counter in build.counters.sorted(by: { $0.winRate < $1.winRate }).prefix(3)
            where counter.winRate < 0.47 && !taken.contains(counter.championId) && !topPicks.contains(counter.championId) {
                let wr = laneEntries.first { $0.championId == counter.championId }
                result.append(BanSuggestion(championId: counter.championId, winRate: wr?.winRate ?? 0, banRate: wr?.banRate ?? 0,
                                            reason: tr("Beats your top pick %@ (%@)", model.gameData.championName(best.championId), percent(1 - counter.winRate, digits: 0))))
            }
        }
        let threats = laneEntries.filter { !taken.contains($0.championId) && $0.pickRate > 0.01 }
            .sorted { ($0.winRate - 0.5) * 200 + $0.banRate * 40 + $0.pickRate * 20 > ($1.winRate - 0.5) * 200 + $1.banRate * 40 + $1.pickRate * 20 }
        for entry in threats where !result.contains(where: { $0.championId == entry.championId }) && !topPicks.contains(entry.championId) && result.count < 5 {
            result.append(BanSuggestion(championId: entry.championId, winRate: entry.winRate, banRate: entry.banRate,
                                        reason: tr("%@ tier · banned in %@ of games", tierName(entry.tier), percent(entry.banRate, digits: 0))))
        }
        return result
    }

    // MARK: Focus champion

    private func refreshFocus(champion: Int, enemyIds: [Int], model: AppModel) async {
        builds = [:]
        riotRunes = []
        gamePlan = []
        guard champion > 0, let client = model.client else { return }
        loadingFocus = true
        defer { loadingFocus = false }
        _ = await model.gameData.detail(champion, client: client)

        let mode = model.queueMode
        let lane = self.lane
        async let riot = try? BuildService.riotRecommended(client: client, championId: champion, lane: lane, mapId: mode.mapId)
        var loaded: [EloTier: ChampionBuild] = [:]
        let tiers: [EloTier] = focusLocked || mode == .ranked ? EloTier.allCases : [.emeraldPlus]
        await withTaskGroup(of: (EloTier, ChampionBuild?).self) { group in
            for tier in tiers {
                group.addTask { (tier, try? await BuildService.opggBuild(championId: champion, lane: lane, mode: mode, tier: tier)) }
            }
            for await (tier, build) in group { if let build { loaded[tier] = build } }
        }
        guard !Task.isCancelled else { return }
        builds = loaded
        riotRunes = await riot ?? []
        if let build = loaded[.emeraldPlus] { BuildCacheSnapshot.last[champion] = build }
        gamePlan = plan(champion: champion, enemyIds: enemyIds, model: model)
    }

    /// Strategy notes derived from the build curve, the lane matchup and both compositions.
    private func plan(champion: Int, enemyIds: [Int], model: AppModel) -> [Tip] {
        var tips: [Tip] = []
        guard let build else { return tips }
        let name = model.gameData.championName(champion)

        if let early = build.gameLengths.first?.winRate, let late = build.gameLengths.last?.winRate {
            if late - early >= 0.04 {
                tips.append(Tip(symbol: "chart.line.uptrend.xyaxis", text: tr("%@ scales: %@ WR in short games vs %@ in long ones. Play safe early and farm.", name, percent(early, digits: 0), percent(late, digits: 0)), tone: .info))
            } else if early - late >= 0.04 {
                tips.append(Tip(symbol: "hare.fill", text: tr("%@ is strongest early (%@ WR in short games). Snowball and close before 30 minutes.", name, percent(early, digits: 0)), tone: .info))
            }
        }
        if let opponent = laneOpponent, let m = build.counters.first(where: { $0.championId == opponent }) {
            let opp = model.gameData.championName(opponent)
            if m.winRate >= 0.52 {
                tips.append(Tip(symbol: "flame.fill", text: tr("Favoured lane vs %@ (%@). Play aggressively and trade often.", opp, percent(m.winRate, digits: 0)), tone: .good))
            } else if m.winRate <= 0.48 {
                tips.append(Tip(symbol: "shield.fill", text: tr("Hard lane vs %@ (%@). Play safe, farm under tower and ask your jungler for help.", opp, percent(m.winRate, digits: 0)), tone: .warning))
            } else {
                tips.append(Tip(symbol: "equal.circle.fill", text: tr("Even lane vs %@ (%@). Skill and jungle pressure decide it; track their jungler.", opp, percent(m.winRate, digits: 0)), tone: .info))
            }
        }
        if let skill = build.skillOrder {
            tips.append(Tip(symbol: "list.number", text: tr("Max %@ (%@ of players).", skill.priority.joined(separator: " → "), percent(skill.pickRate, digits: 0)), tone: .info))
        }
        if let core = build.coreItems.first {
            let items = core.ids.compactMap { model.gameData.items[$0]?.name }.joined(separator: " → ")
            tips.append(Tip(symbol: "bag.fill", text: tr("Core: %@ (%@ WR).", items, percent(core.winRate, digits: 0)), tone: .info))
        }
        return tips + compTips.filter { $0.tone != .good }
    }

    // MARK: Compositions

    private func refreshComps(allyIds: [Int], enemyIds: [Int], model: AppModel) async {
        for id in allyIds + enemyIds { _ = await model.gameData.detail(id, client: model.client) }
        ally = TeamComposition(champions: allyIds, details: model.gameData.details)
        enemy = TeamComposition(champions: enemyIds, details: model.gameData.details)
        var tips: [Tip] = []
        if ally.count >= 3 {
            if ally.physicalShare >= 0.8 { tips.append(Tip(symbol: "exclamationmark.triangle.fill", text: tr("Your team is almost all physical damage. The enemy can stack armor; a magic damage pick helps."), tone: .warning)) }
            if ally.magicShare >= 0.8 { tips.append(Tip(symbol: "exclamationmark.triangle.fill", text: tr("Your team is almost all magic damage. The enemy can stack magic resist; a physical damage pick helps."), tone: .warning)) }
            if ally.frontline / Double(ally.count) < 1.5 { tips.append(Tip(symbol: "shield.slash", text: tr("Little frontline so far. A tank or bruiser would help."), tone: .warning)) }
            if ally.crowdControl / Double(ally.count) < 1.4 { tips.append(Tip(symbol: "tortoise", text: tr("Low crowd control. Pick engage or lockdown if you can."), tone: .warning)) }
        }
        if enemy.count >= 3 {
            if enemy.magicShare >= 0.6 { tips.append(Tip(symbol: "sparkles", text: tr("Enemy is magic-heavy: magic resist and Mercury's Treads are valuable."), tone: .info)) }
            if enemy.physicalShare >= 0.6 { tips.append(Tip(symbol: "shield.lefthalf.filled", text: tr("Enemy is physical-heavy: armor and Plated Steelcaps are valuable."), tone: .info)) }
            if enemy.crowdControl / Double(enemy.count) >= 2.2 { tips.append(Tip(symbol: "figure.fall", text: tr("Enemy has a lot of crowd control: tenacity or a cleanse effect helps."), tone: .info)) }
            if enemy.mobility / Double(enemy.count) >= 2.2 { tips.append(Tip(symbol: "hare", text: tr("Enemy is very mobile: save your crowd control for their dive."), tone: .info)) }
        }
        compTips = tips
    }
}

/// Last emerald+ build per champion, used for counter-based ban hints.
@MainActor
enum BuildCacheSnapshot {
    static var last: [Int: ChampionBuild] = [:]
}

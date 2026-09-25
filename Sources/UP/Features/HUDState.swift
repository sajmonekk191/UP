import Foundation

enum HUDMode: Sendable {
    case hud, scoreboard
}

struct Toast: Identifiable, Hashable {
    enum Tone { case good, warning, info, danger }
    let id = UUID()
    let date = Date()
    var symbol: String
    var text: String
    var tone: Tone
}

/// One enemy or ally row in the HUD, derived from the live snapshot.
struct HUDPlayer: Identifiable, Hashable {
    var id: String
    var championName: String
    var championId: Int?
    var position: String?
    var level: Int
    var isDead: Bool
    var respawn: Double
    var kills: Int, deaths: Int, assists: Int
    var completedItems: [Int]
    var counterItems: [Int]
    var items: [Int]
}

/// Next core item for the local player and how much gold is still missing.
struct ItemGoal: Hashable {
    var itemId: Int
    var name: String
    var remaining: Int
    var total: Int
}

/// In-game HUD state: player rows, the gold goal and event toasts built by diffing live snapshots.
@MainActor
@Observable
final class HUDState {
    private(set) var enemies: [HUDPlayer] = []
    private(set) var goal: ItemGoal?
    private(set) var toasts: [Toast] = []
    private(set) var csPerMinute = 0.0
    private(set) var myBuild: ChampionBuild?
    private(set) var myChampionId: Int?

    private var previous: [String: HUDPlayer] = [:]
    private var announced: Set<String> = []
    private var requestedDetails: Set<Int> = []
    private var coreItems: [Int] = []
    private var buildKey = ""
    private var lastEventId = -1
    private var isFirst = true

    func reset() {
        enemies = []; goal = nil; toasts = []; csPerMinute = 0; myBuild = nil; myChampionId = nil
        previous = [:]; announced = []; requestedDetails = []; coreItems = []; buildKey = ""; lastEventId = -1; isFirst = true
    }

    func ingest(_ live: LiveGameSnapshot, model: AppModel) {
        let data = model.gameData
        var rows: [HUDPlayer] = [], enemyRows: [HUDPlayer] = []
        for player in live.players {
            let owned = player.items.map(\.itemID)
            let row = HUDPlayer(id: player.id, championName: player.championName,
                                championId: data.champion(named: player.championName)?.id, position: player.position,
                                level: player.level, isDead: player.isDead, respawn: player.respawnTimer ?? 0,
                                kills: player.scores.kills, deaths: player.scores.deaths, assists: player.scores.assists,
                                completedItems: owned.filter { id in
                                    guard let item = data.items[id] else { return false }
                                    return (item.priceTotal ?? 0) >= 2200 && (item.to ?? []).isEmpty
                                },
                                counterItems: owned.filter { LiveGameAnalyzer.counterItems[$0] != nil },
                                items: player.items.filter { ($0.slot ?? 0) < 6 }.sorted { ($0.slot ?? 0) < ($1.slot ?? 0) }.map(\.itemID))
            rows.append(row)
            if player.team != live.myTeam { enemyRows.append(row) }
        }

        let missing = rows.compactMap(\.championId).filter { data.details[$0] == nil && !requestedDetails.contains($0) }
        if !missing.isEmpty, let client = model.client {
            requestedDetails.formUnion(missing)
            Task { await data.prefetchDetails(missing, client: client) }
        }
        if isFirst {
            lastEventId = live.announcements.map(\.id).max() ?? -1
        } else {
            diff(enemies: enemyRows, live: live, model: model)
        }
        if enemies != enemyRows { enemies = enemyRows }
        previous = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        isFirst = false

        if let me = live.me {
            csPerMinute = Double(me.scores.creepScore) / max(live.gameTime / 60, 1)
            updateGoal(me: me, gold: live.currentGold ?? 0, model: model)
        }
        objectiveCalls(live)
        let current = toasts.filter { Date().timeIntervalSince($0.date) <= 10 }
        if current.count != toasts.count { toasts = current }
    }

    // MARK: Events

    private func diff(enemies: [HUDPlayer], live: LiveGameSnapshot, model: AppModel) {
        let myPosition = live.me?.position
        for enemy in enemies {
            guard let before = previous[enemy.id] else { continue }
            let important = enemy.position == "JUNGLE" || (myPosition != nil && enemy.position == myPosition)
            if important, enemy.level > before.level, [6, 11, 16].contains(enemy.level) {
                push("bolt.circle.fill", tr("%@ reached level %d: ultimate rank up", enemy.championName, enemy.level), .warning)
            }
            for item in enemy.completedItems where !before.completedItems.contains(item) {
                push("shield.lefthalf.filled", tr("%@ completed %@", enemy.championName, model.gameData.items[item]?.name ?? "?"), .info)
            }
            if enemy.isDead, !before.isDead, enemy.position == "JUNGLE", enemy.respawn >= 20 {
                push("figure.fall", tr("Enemy jungler %@ is dead for %ds: invade or take an objective", enemy.championName, Int(enemy.respawn)), .good)
            }
        }
        let deadEnemies = enemies.filter(\.isDead)
        let wasDead = enemies.filter { previous[$0.id]?.isDead == true }.count
        if deadEnemies.count >= 3, wasDead < 3 {
            let window = Int(deadEnemies.map(\.respawn).min() ?? 0)
            push("flag.fill", tr("%d enemies dead for at least %ds: push or take an objective", deadEnemies.count, window), .good)
        }
        if let me = live.me, me.isDead, previous[me.id]?.isDead == false, (me.respawnTimer ?? 0) >= 25 {
            push("clock.fill", tr("You respawn in %ds. Plan your next item and path.", Int(me.respawnTimer ?? 0)), .info)
        }
        for event in live.announcements where event.id > lastEventId {
            push(event.symbol, event.text, event.ally ? .good : .danger)
        }
        lastEventId = max(lastEventId, live.announcements.map(\.id).max() ?? -1)
    }

    private func objectiveCalls(_ live: LiveGameSnapshot) {
        for objective in live.objectives {
            guard let at = objective.respawnAt else { continue }
            let left = at - live.gameTime
            let key = "\(objective.name)-\(Int(at))"
            if left <= 60, left > 50, !announced.contains(key) {
                announced.insert(key)
                push(objective.symbol, tr("%@ spawns in %@", objective.name, formatTime(left)), .warning)
            }
        }
        for (team, count) in [(tr("Your team"), live.ally.dragons.filter { $0.lowercased() != "elder" }.count),
                              (tr("Enemy"), live.enemy.dragons.filter { $0.lowercased() != "elder" }.count)] where count == 3 {
            let key = "soul-\(team)"
            if !announced.contains(key) {
                announced.insert(key)
                push("flame.circle.fill", tr("%@ is on soul point", team), .warning)
            }
        }
    }

    // MARK: Gold goal

    private func updateGoal(me: LivePlayer, gold: Double, model: AppModel) {
        let championId = model.gameData.champion(named: me.championName)?.id ?? 0
        let lane = Lane(clientPosition: me.position)
        let key = "\(championId)-\(lane?.rawValue ?? "-")"
        if key != buildKey, championId > 0 {
            buildKey = key
            Task {
                let mode: QueueMode = model.queueMode
                if mode == .arena { await model.gameData.loadAugments(client: model.client) }
                var build = try? await BuildService.opggBuild(championId: championId, lane: lane, mode: mode)
                if build == nil, lane != nil { build = try? await BuildService.opggBuild(championId: championId, lane: nil, mode: mode) }
                guard let build else {
                    try? await Task.sleep(for: .seconds(20))
                    if buildKey == key { buildKey = "" }
                    return
                }
                myBuild = build
                myChampionId = championId
                coreItems = (build.boots.first?.ids ?? []) + (build.coreItems.first?.ids ?? []) + build.lastItems.prefix(3).flatMap(\.ids)
            }
        }
        let owned = me.items.map(\.itemID)
        guard let next = coreItems.first(where: { !owned.contains($0) }), let item = model.gameData.items[next] else {
            if goal != nil { goal = nil }
            return
        }
        let total = item.priceTotal ?? 0
        let componentValue = (item.from ?? []).filter { owned.contains($0) }.reduce(0) { $0 + (model.gameData.items[$1]?.priceTotal ?? 0) }
        let remaining = max(total - componentValue - Int(gold), 0)
        if remaining == 0, goal?.itemId == next, (goal?.remaining ?? 0) > 0 {
            push("bag.fill.badge.plus", tr("You can buy %@ now", item.name), .good)
        }
        let newGoal = ItemGoal(itemId: next, name: item.name, remaining: remaining, total: max(total - componentValue, 1))
        if goal != newGoal { goal = newGoal }
    }

    private func push(_ symbol: String, _ text: String, _ tone: Toast.Tone) {
        guard !toasts.contains(where: { $0.text == text }) else { return }
        toasts.append(Toast(symbol: symbol, text: text, tone: tone))
        if toasts.count > 4 { toasts.removeFirst(toasts.count - 4) }
    }
}

import Foundation

/// Objective timers, team summaries and item alerts derived from Live Client Data.
struct LiveGameSnapshot: Sendable {
    struct Objective: Sendable, Identifiable, Hashable {
        var name: String
        var symbol: String
        var respawnAt: Double?
        var note: String?
        var id: String { name }
    }

    struct TeamSummary: Sendable {
        var team: String
        var kills = 0
        var itemGold = 0
        var cs = 0
        var levels = 0
        var dragons: [String] = []
        var barons = 0
        var towers = 0
        var grubs = 0
        var heralds = 0
    }

    struct ItemAlert: Sendable, Identifiable, Hashable {
        var player: String
        var champion: String
        var itemId: Int
        var itemName: String
        var advice: String
        var id: String { player + String(itemId) }
    }

    struct FeedItem: Sendable, Identifiable, Hashable {
        enum Side: Sendable { case ally, enemy, neutral }
        var id: Int
        var time: Double
        var text: String
        var symbol: String
        var side: Side
    }

    var gameTime: Double
    var gameMode: String
    var me: LivePlayer?
    var activeStats: LiveActivePlayer.Stats?
    var currentGold: Double?
    var feed: [FeedItem] = []
    var myTeam: String
    var players: [LivePlayer]
    var objectives: [Objective]
    var ally: TeamSummary
    var enemy: TeamSummary
    var alerts: [ItemAlert]
    var inhibitors: [Inhibitor]

    struct Inhibitor: Sendable, Hashable, Identifiable {
        var lane: String
        var ours: Bool
        var respawnAt: Double
        var id: String { "\(ours)-\(lane)" }
        var name: String {
            switch (ours, lane) {
            case (true, "top"): tr("Our top inhibitor")
            case (true, "mid"): tr("Our mid inhibitor")
            case (true, _): tr("Our bot inhibitor")
            case (false, "top"): tr("Enemy top inhibitor")
            case (false, "mid"): tr("Enemy mid inhibitor")
            case (false, _): tr("Enemy bot inhibitor")
            }
        }
    }

    var goldDiff: Int { ally.itemGold - enemy.itemGold }
}

enum LiveGameAnalyzer {
    /// Respawn and first-spawn times in seconds for the current Summoner's Rift ruleset.
    static let dragonRespawn = 300.0
    static let baronRespawn = 360.0
    static let elderRespawn = 360.0
    static let inhibitorRespawn = 300.0
    static let dragonFirstSpawn = 300.0
    static let baronFirstSpawn = 1500.0

    static let counterItems: [Int: String] = [
        3157: "Zhonya's: wait for the stasis to end before using your burst.",
        2420: "Stopwatch: can use stasis once.",
        3026: "Guardian Angel: revives after death, keep your ult or CC.",
        3140: "QSS: removes CC, don't open a fight with CC alone.",
        6035: "Silvermere Dawn: removes CC.",
        3139: "Mercurial: removes CC.",
        3102: "Banshee's Veil: pop the shield with a weaker ability first.",
        3814: "Edge of Night: pop the shield with a weaker ability first.",
        3033: "Mortal Reminder: reduced healing, consider a counter item.",
        3075: "Thornmail: reduced healing when attacking.",
        3165: "Morellonomicon: reduced healing.",
        3916: "Oblivion Orb: reduced healing.",
        6609: "Chempunk Chainsword: reduced healing.",
        6695: "Serpent's Fang: weakens shields.",
        3143: "Randuin's Omen: less damage from crits.",
        3110: "Frozen Heart: lower attack speed.",
        3065: "Spirit Visage: stronger enemy healing.",
        3156: "Maw of Malmortius: magic damage shield.",
    ]

    static func analyze(_ data: LiveGameData, items: [Int: ItemInfo]) -> LiveGameSnapshot {
        let time = data.gameData.gameTime
        let myName = data.activePlayer?.riotId ?? data.activePlayer?.summonerName
        let me = data.allPlayers.first { $0.riotId == myName || $0.summonerName == myName }
        let myTeam = me?.team ?? "ORDER"

        func team(of name: String?) -> String? {
            guard let name else { return nil }
            if let player = data.allPlayers.first(where: {
                $0.riotIdGameName == name || $0.riotId == name || $0.summonerName == name
            }) { return player.team }
            if name.contains("T100") || name.contains("Order") { return "ORDER" }
            if name.contains("T200") || name.contains("Chaos") { return "CHAOS" }
            return nil
        }

        var ally = LiveGameSnapshot.TeamSummary(team: myTeam)
        var enemy = LiveGameSnapshot.TeamSummary(team: myTeam == "ORDER" ? "CHAOS" : "ORDER")
        for player in data.allPlayers {
            let gold = player.items.reduce(0) { $0 + (items[$1.itemID]?.priceTotal ?? 0) * max($1.count ?? 1, 1) }
            if player.team == myTeam {
                ally.kills += player.scores.kills; ally.itemGold += gold; ally.cs += player.scores.creepScore; ally.levels += player.level
            } else {
                enemy.kills += player.scores.kills; enemy.itemGold += gold; enemy.cs += player.scores.creepScore; enemy.levels += player.level
            }
        }

        var lastDragon: LiveEvent?, lastBaron: LiveEvent?
        var inhibitors: [String: (respawnAt: Double, ours: Bool)] = [:]
        for event in data.events.Events {
            let killerTeam = team(of: event.KillerName)
            func credit(_ update: (inout LiveGameSnapshot.TeamSummary) -> Void) {
                if killerTeam == myTeam { update(&ally) } else if killerTeam != nil { update(&enemy) }
            }
            switch event.EventName {
            case "DragonKill":
                lastDragon = event
                credit { $0.dragons.append(event.DragonType ?? "?") }
            case "BaronKill":
                lastBaron = event
                credit { $0.barons += 1 }
            case "HeraldKill": credit { $0.heralds += 1 }
            case "HordeKill": credit { $0.grubs += 1 }
            case "TurretKilled": credit { $0.towers += 1 }
            case "InhibKilled":
                if let inhib = event.InhibKilled {
                    let ours = killerTeam.map { $0 != myTeam } ?? (inhib.contains("T1") == (myTeam == "ORDER"))
                    inhibitors[inhib] = (event.EventTime + inhibitorRespawn, ours)
                }
            case "InhibRespawned":
                if let inhib = event.InhibKilled { inhibitors[inhib] = nil }
            default: break
            }
        }

        var objectives: [LiveGameSnapshot.Objective] = []
        if let dragon = lastDragon {
            let elder = dragon.DragonType?.lowercased() == "elder"
            let soul = ally.dragons.filter { $0.lowercased() != "elder" }.count >= 4 || enemy.dragons.filter { $0.lowercased() != "elder" }.count >= 4
            objectives.append(.init(name: soul || elder ? tr("Elder dragon") : tr("Dragon"), symbol: "flame",
                                    respawnAt: dragon.EventTime + (soul || elder ? elderRespawn : dragonRespawn),
                                    note: tr("Last: %@", dragon.DragonType ?? "?")))
        } else {
            objectives.append(.init(name: tr("Dragon"), symbol: "flame", respawnAt: dragonFirstSpawn, note: tr("First spawn")))
        }
        objectives.append(.init(name: "Baron", symbol: "crown",
                                respawnAt: lastBaron.map { $0.EventTime + baronRespawn } ?? baronFirstSpawn,
                                note: lastBaron == nil ? tr("First spawn") : tr("Buff until %@", formatTime((lastBaron?.EventTime ?? 0) + 180))))

        let alerts = data.allPlayers.filter { $0.team != myTeam }.flatMap { player in
            player.items.compactMap { item -> LiveGameSnapshot.ItemAlert? in
                guard let advice = counterItems[item.itemID].map({ tr($0) }) else { return nil }
                return .init(player: player.name, champion: player.championName, itemId: item.itemID,
                             itemName: items[item.itemID]?.name ?? item.displayName ?? "#\(item.itemID)", advice: advice)
            }
        }

        func champion(_ name: String?) -> String {
            guard let name else { return "?" }
            return data.allPlayers.first { $0.riotIdGameName == name || $0.riotId == name || $0.summonerName == name }?.championName ?? name
        }
        let feed = data.events.Events.suffix(40).reversed().compactMap { e -> LiveGameSnapshot.FeedItem? in
            let side: LiveGameSnapshot.FeedItem.Side = switch team(of: e.KillerName) {
            case myTeam: .ally
            case nil: .neutral
            default: .enemy
            }
            let text: String, symbol: String
            switch e.EventName {
            case "ChampionKill":
                let assists = (e.Assisters ?? []).map { champion($0) }
                text = tr("%@ killed %@", champion(e.KillerName), champion(e.VictimName)) + (assists.isEmpty ? "" : " (+\(assists.joined(separator: ", ")))")
                symbol = "bolt.fill"
            case "Multikill":
                text = "\(champion(e.KillerName)): \(["", "", "Double", "Triple", "Quadra", "PENTA"][min(e.KillStreak ?? 2, 5)]) kill"
                symbol = "flame.fill"
            case "FirstBlood": text = tr("First blood: %@", champion(e.KillerName)); symbol = "drop.fill"
            case "DragonKill": text = tr("%@ took the %@ dragon", champion(e.KillerName), e.DragonType ?? "?") + (e.Stolen == "True" ? " – " + tr("STOLEN") : ""); symbol = "flame"
            case "BaronKill": text = tr("%@ took Baron", champion(e.KillerName)) + (e.Stolen == "True" ? " – " + tr("STOLEN") : ""); symbol = "crown.fill"
            case "HeraldKill": text = tr("%@ took the Herald", champion(e.KillerName)); symbol = "eye.fill"
            case "HordeKill": text = tr("%@ took a Voidgrub", champion(e.KillerName)); symbol = "ant.fill"
            case "TurretKilled": text = tr("Turret destroyed (%@)", champion(e.KillerName)); symbol = "building.2.fill"
            case "InhibKilled": text = tr("Inhibitor destroyed (%@)", champion(e.KillerName)); symbol = "building.columns.fill"
            case "Ace": text = "ACE"; symbol = "star.fill"
            default: return nil
            }
            let resolvedSide: LiveGameSnapshot.FeedItem.Side = e.EventName == "Ace" ? (e.AcingTeam == myTeam ? .ally : .enemy) : side
            return .init(id: e.EventID, time: e.EventTime, text: text, symbol: symbol, side: resolvedSide)
        }

        return LiveGameSnapshot(
            gameTime: time, gameMode: data.gameData.gameMode ?? "",
            me: me, activeStats: data.activePlayer?.championStats, currentGold: data.activePlayer?.currentGold,
            feed: Array(feed.prefix(15)), myTeam: myTeam,
            players: data.allPlayers, objectives: objectives, ally: ally, enemy: enemy, alerts: alerts,
            inhibitors: inhibitors.filter { $0.value.respawnAt > time }.map { raw, value in
                let lane = raw.hasSuffix("L1") ? "top" : raw.hasSuffix("C1") ? "mid" : "bot"
                return LiveGameSnapshot.Inhibitor(lane: lane, ours: value.ours, respawnAt: value.respawnAt)
            }.sorted { $0.respawnAt < $1.respawnAt })
    }
}

func formatTime(_ seconds: Double) -> String {
    let s = max(Int(seconds.rounded()), 0)
    return String(format: "%d:%02d", s / 60, s % 60)
}

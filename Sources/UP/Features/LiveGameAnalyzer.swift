import Foundation

/// Objective timers, team summaries and announcements derived from Live Client Data.
struct LiveGameSnapshot: Sendable {
    struct Objective: Sendable, Identifiable, Hashable {
        var name: String
        var symbol: String
        var respawnAt: Double?
        var id: String { name }
    }

    struct TeamSummary: Sendable {
        var kills = 0
        var itemGold = 0
        var dragons: [String] = []
    }

    /// Ace or Baron take worth a pop-up in the HUD.
    struct Announcement: Sendable, Identifiable, Hashable {
        var id: Int
        var text: String
        var symbol: String
        var ally: Bool
    }

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

    var gameTime: Double
    var me: LivePlayer?
    var currentGold: Double?
    var myTeam: String
    var players: [LivePlayer]
    var objectives: [Objective]
    var ally: TeamSummary
    var enemy: TeamSummary
    var inhibitors: [Inhibitor]
    var announcements: [Announcement]
    var abilityLevels: [String: Int] = [:]

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

        func player(named name: String?) -> LivePlayer? {
            guard let name else { return nil }
            return data.allPlayers.first { $0.riotIdGameName == name || $0.riotId == name || $0.summonerName == name }
        }
        func team(of name: String?) -> String? {
            guard let name else { return nil }
            if let player = player(named: name) { return player.team }
            if name.contains("T100") || name.contains("Order") { return "ORDER" }
            if name.contains("T200") || name.contains("Chaos") { return "CHAOS" }
            return nil
        }

        var ally = LiveGameSnapshot.TeamSummary()
        var enemy = LiveGameSnapshot.TeamSummary()
        for player in data.allPlayers {
            let gold = player.items.reduce(0) { $0 + (items[$1.itemID]?.priceTotal ?? 0) * max($1.count ?? 1, 1) }
            if player.team == myTeam {
                ally.kills += player.scores.kills
                ally.itemGold += gold
            } else {
                enemy.kills += player.scores.kills
                enemy.itemGold += gold
            }
        }

        var lastDragon: LiveEvent?, lastBaron: LiveEvent?
        var inhibitors: [String: (respawnAt: Double, ours: Bool)] = [:]
        var announcements: [LiveGameSnapshot.Announcement] = []
        for event in data.events.Events {
            let killerTeam = team(of: event.KillerName)
            switch event.EventName {
            case "DragonKill":
                lastDragon = event
                if killerTeam == myTeam { ally.dragons.append(event.DragonType ?? "?") } else if killerTeam != nil { enemy.dragons.append(event.DragonType ?? "?") }
            case "BaronKill":
                lastBaron = event
                let killer = player(named: event.KillerName)?.championName ?? event.KillerName ?? "?"
                announcements.append(.init(id: event.EventID, text: tr("%@ took Baron", killer) + (event.Stolen == "True" ? " – " + tr("STOLEN") : ""),
                                           symbol: "crown.fill", ally: killerTeam == myTeam))
            case "Ace":
                announcements.append(.init(id: event.EventID, text: "ACE", symbol: "star.fill", ally: event.AcingTeam == myTeam))
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
                                    respawnAt: dragon.EventTime + (soul || elder ? elderRespawn : dragonRespawn)))
        } else {
            objectives.append(.init(name: tr("Dragon"), symbol: "flame", respawnAt: dragonFirstSpawn))
        }
        objectives.append(.init(name: "Baron", symbol: "crown", respawnAt: lastBaron.map { $0.EventTime + baronRespawn } ?? baronFirstSpawn))

        return LiveGameSnapshot(
            gameTime: time, me: me, currentGold: data.activePlayer?.currentGold, myTeam: myTeam,
            players: data.allPlayers, objectives: objectives, ally: ally, enemy: enemy,
            inhibitors: inhibitors.filter { $0.value.respawnAt > time }.map { raw, value in
                let lane = raw.hasSuffix("L1") ? "top" : raw.hasSuffix("C1") ? "mid" : "bot"
                return LiveGameSnapshot.Inhibitor(lane: lane, ours: value.ours, respawnAt: value.respawnAt)
            }.sorted { $0.respawnAt < $1.respawnAt },
            announcements: announcements, abilityLevels: data.activePlayer?.abilityLevels ?? [:])
    }
}

func formatTime(_ seconds: Double) -> String {
    let s = max(Int(seconds.rounded()), 0)
    return String(format: "%d:%02d", s / 60, s % 60)
}

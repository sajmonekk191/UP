import Foundation

/// Scripted sample game used to preview the in-game HUD without playing.
enum HUDPreview {
    static let start = 14 * 60.0 + 10

    static func data(elapsed: Double) -> LiveGameData {
        let time = start + elapsed
        func player(_ champ: String, _ name: String, _ team: String, _ pos: String, level: Int, k: Int, d: Int, a: Int, cs: Int,
                    items: [Int], dead: Bool = false, respawn: Double = 0) -> LivePlayer {
            LivePlayer(championName: champ, riotId: "\(name)#EUW", riotIdGameName: name, summonerName: name,
                       team: team, level: level, isDead: dead, respawnTimer: respawn, position: pos,
                       scores: .init(kills: k, deaths: d, assists: a, creepScore: cs),
                       items: items.enumerated().map { .init(itemID: $0.element, count: 1, slot: $0.offset) })
        }
        let zedLevel = elapsed >= 4 ? 11 : 10
        let viDead = elapsed >= 7 && elapsed < 39
        let zedItems = elapsed >= 11 ? [3142, 3814, 3158, 3157] : [3142, 3814, 3158]
        let gold = 900 + elapsed * 60
        let players = [
            player("Ahri", "You", "ORDER", "MIDDLE", level: 11, k: 5, d: 2, a: 6, cs: 118, items: [3020, 3118, 4645]),
            player("Garen", "Tank Man", "ORDER", "TOP", level: 10, k: 2, d: 3, a: 1, cs: 102, items: [3047, 3078, 3053]),
            player("LeeSin", "Kick", "ORDER", "JUNGLE", level: 10, k: elapsed >= 7 ? 5 : 4, d: 3, a: 7, cs: 81, items: [6692, 3158, 3071]),
            player("Caitlyn", "Headshot", "ORDER", "BOTTOM", level: 9, k: 3, d: 1, a: 4, cs: 131, items: [3006, 3031, 6672]),
            player("Lulu", "Pix", "ORDER", "UTILITY", level: 8, k: 0, d: 2, a: 11, cs: 20, items: [3158, 6617]),
            player("Zed", "Shadow", "CHAOS", "MIDDLE", level: zedLevel, k: 6, d: 3, a: 2, cs: 122, items: zedItems),
            player("Vi", "Punch", "CHAOS", "JUNGLE", level: 9, k: 2, d: viDead ? 5 : 4, a: 5, cs: 76, items: [3071, 3047, 1036, 1028],
                   dead: viDead, respawn: viDead ? 39 - elapsed : 0),
            player("Darius", "Axe", "CHAOS", "TOP", level: 11, k: 3, d: 2, a: 1, cs: 110, items: [6631, 3047, 3053]),
            player("Jinx", "Rockets", "CHAOS", "BOTTOM", level: 9, k: 1, d: 3, a: 3, cs: 126, items: [3006, 6672, 1055, 1042, 2003]),
            player("Thresh", "Lantern", "CHAOS", "UTILITY", level: 8, k: 0, d: 2, a: 6, cs: 18, items: [3111, 3190]),
        ]
        let events = [
            LiveEvent(EventID: 3, EventName: "DragonKill", EventTime: 420, KillerName: "Kick", DragonType: "Fire", Stolen: "False"),
            LiveEvent(EventID: 5, EventName: "DragonKill", EventTime: 625, KillerName: "Kick", DragonType: "Water", Stolen: "False"),
            LiveEvent(EventID: 7, EventName: "InhibKilled", EventTime: start - 40, KillerName: "Kick", InhibKilled: "Barracks_T2_C1"),
            LiveEvent(EventID: 8, EventName: "InhibKilled", EventTime: start - 100, KillerName: "Axe", InhibKilled: "Barracks_T1_L1"),
        ]
        return LiveGameData(
            activePlayer: LiveActivePlayer(riotId: "You#EUW", summonerName: "You", currentGold: gold),
            allPlayers: players,
            events: LiveEvents(Events: events),
            gameData: LiveGameStats(gameTime: time))
    }

    /// Sample scouted profiles for the preview's match overview, keyed by live champion name.
    static let profiles: [String: PlayerProfile] = {
        let roster: [(String, Int, String, String, String, Int, Int, Int, Int, Int, String)] = [
            ("Ahri", 103, "You", "EMERALD", "II", 41, 88, 71, 142_000, 9, "WWLWWLWLWW"),
            ("Garen", 86, "Tank Man", "PLATINUM", "I", 12, 54, 58, 38_000, 3, "LWLLWWLWLW"),
            ("LeeSin", 64, "Kick", "EMERALD", "IV", 77, 120, 101, 410_000, 12, "WWWLWWLWWL"),
            ("Caitlyn", 51, "Headshot", "EMERALD", "III", 5, 61, 60, 22_000, 2, "LWWLLWLWWL"),
            ("Lulu", 117, "Pix", "PLATINUM", "II", 60, 40, 44, 9_000, 0, "LLWLWLLWWL"),
            ("Zed", 238, "Shadow", "DIAMOND", "IV", 18, 131, 109, 610_000, 15, "WWWWLWWLWW"),
            ("Vi", 254, "Punch", "EMERALD", "I", 33, 70, 66, 4_000, 0, "LWLLLWLWLL"),
            ("Darius", 122, "Axe", "EMERALD", "II", 90, 64, 52, 95_000, 5, "WLWWLWWLWL"),
            ("Jinx", 222, "Rockets", "PLATINUM", "I", 71, 45, 49, 31_000, 4, "LLWLWWLLWL"),
            ("Thresh", 412, "Lantern", "EMERALD", "III", 22, 83, 80, 260_000, 7, "WLWLWWLWLW"),
        ]
        var result: [String: PlayerProfile] = [:]
        for (index, entry) in roster.enumerated() {
            let (champ, champId, name, tier, division, lp, wins, losses, points, champGames, form) = entry
            let recent = form.enumerated().map { i, ch in
                HistoryGame(gameId: index * 100 + i, gameCreation: (Date().timeIntervalSince1970 - Double(i) * 7200) * 1000,
                            gameDuration: 1800, gameMode: "CLASSIC", gameType: "MATCHED_GAME", queueId: 420,
                            participants: [HistoryParticipant(championId: i < champGames ? champId : 1,
                                                              stats: HistoryStats(win: ch == "W", kills: 2 + (i + index * 3) % 8, deaths: 2 + (i + index) % 6, assists: 3 + (i * 2 + index) % 9))])
            }
            var profile = PlayerProfile(
                puuid: "preview-\(index)",
                summoner: Summoner(puuid: "preview-\(index)", gameName: name, tagLine: "EUW", summonerLevel: 120 + index * 37),
                solo: RankedQueue(tier: tier, division: division, leaguePoints: lp, wins: wins, losses: losses),
                flex: nil, recent: recent,
                champions: champGames > 0 ? [.init(championId: champId, games: champGames, wins: champGames * 3 / 5, kills: 40, deaths: 25, assists: 50)] : [])
            profile.masteries = [ChampionMastery(championId: champId, championLevel: points > 100_000 ? 10 : points > 20_000 ? 6 : 3, championPoints: points)]
            result[champ] = profile
        }
        return result
    }()
}

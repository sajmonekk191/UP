import Foundation

/// Riot's official in-game Live Client Data API (only reachable while a game runs).
enum LiveClient {
    static func allGameData() async throws -> LiveGameData {
        let url = URL(string: "https://127.0.0.1:2999/liveclientdata/allgamedata")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        let (data, response) = try await localhostSession.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LCUError.http(0, "Live client not ready") }
        return try jsonDecoder.decode(LiveGameData.self, from: data)
    }
}

struct LiveGameData: Decodable, Sendable {
    var activePlayer: LiveActivePlayer?
    var allPlayers: [LivePlayer]
    var events: LiveEvents
    var gameData: LiveGameStats

    init(activePlayer: LiveActivePlayer?, allPlayers: [LivePlayer], events: LiveEvents, gameData: LiveGameStats) {
        self.activePlayer = activePlayer
        self.allPlayers = allPlayers
        self.events = events
        self.gameData = gameData
    }

    /// Skips malformed entries (e.g. Practice Tool placeholders) instead of failing the whole snapshot.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activePlayer = try? c.decodeIfPresent(LiveActivePlayer.self, forKey: .activePlayer)
        allPlayers = (try c.decodeIfPresent([Lossy<LivePlayer>].self, forKey: .allPlayers) ?? [])
            .compactMap(\.value).filter { !$0.championName.isEmpty }
        events = (try? c.decodeIfPresent(LiveEvents.self, forKey: .events)) ?? LiveEvents(Events: [])
        gameData = try c.decode(LiveGameStats.self, forKey: .gameData)
    }

    private enum CodingKeys: String, CodingKey { case activePlayer, allPlayers, events, gameData }
}

/// Decodes an element if possible and yields nil instead of throwing.
struct Lossy<Value: Decodable & Sendable>: Decodable, Sendable {
    let value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

struct LiveActivePlayer: Decodable, Sendable {
    var riotId: String?
    var summonerName: String?
    var currentGold: Double?
    /// Points spent per ability key: Q, W, E and R.
    var abilityLevels: [String: Int] = [:]

    init(riotId: String?, summonerName: String?, currentGold: Double?, abilityLevels: [String: Int] = [:]) {
        self.riotId = riotId; self.summonerName = summonerName; self.currentGold = currentGold; self.abilityLevels = abilityLevels
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        riotId = try? c.decodeIfPresent(String.self, forKey: .riotId)
        summonerName = try? c.decodeIfPresent(String.self, forKey: .summonerName)
        currentGold = try? c.decodeIfPresent(Double.self, forKey: .currentGold)
        let abilities = (try? c.decodeIfPresent([String: Lossy<Ability>].self, forKey: .abilities)) ?? [:]
        abilityLevels = abilities.compactMapValues { $0.value?.abilityLevel }
    }

    private struct Ability: Decodable, Sendable { var abilityLevel: Int? }
    private enum CodingKeys: String, CodingKey { case riotId, summonerName, currentGold, abilities }
}

struct LivePlayer: Decodable, Sendable, Identifiable, Hashable {
    struct Scores: Decodable, Sendable, Hashable {
        var kills: Int
        var deaths: Int
        var assists: Int
        var creepScore: Int

        init(kills: Int, deaths: Int, assists: Int, creepScore: Int) {
            self.kills = kills; self.deaths = deaths; self.assists = assists; self.creepScore = creepScore
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kills = (try? c.decodeIfPresent(Int.self, forKey: .kills)) ?? 0
            deaths = (try? c.decodeIfPresent(Int.self, forKey: .deaths)) ?? 0
            assists = (try? c.decodeIfPresent(Int.self, forKey: .assists)) ?? 0
            creepScore = (try? c.decodeIfPresent(Int.self, forKey: .creepScore)) ?? 0
        }

        private enum CodingKeys: String, CodingKey { case kills, deaths, assists, creepScore }
    }
    struct Item: Decodable, Sendable, Hashable {
        var itemID: Int
        var count: Int?
        var slot: Int?
    }

    var championName: String
    var riotId: String?
    var riotIdGameName: String?
    var summonerName: String?
    var team: String
    var level: Int
    var isDead: Bool
    var respawnTimer: Double?
    var position: String?
    var scores: Scores
    var items: [Item]

    var id: String { (riotId ?? summonerName ?? "") + championName }
    var name: String { riotIdGameName ?? riotId ?? summonerName ?? championName }

    init(championName: String, riotId: String?, riotIdGameName: String?, summonerName: String?,
         team: String, level: Int, isDead: Bool, respawnTimer: Double?, position: String?, scores: Scores, items: [Item]) {
        self.championName = championName; self.riotId = riotId; self.riotIdGameName = riotIdGameName
        self.summonerName = summonerName; self.team = team; self.level = level
        self.isDead = isDead; self.respawnTimer = respawnTimer; self.position = position; self.scores = scores
        self.items = items
    }

    /// Missing optional data falls back to defaults so one odd entry never drops a real player.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        championName = try c.decode(String.self, forKey: .championName)
        riotId = try? c.decodeIfPresent(String.self, forKey: .riotId)
        riotIdGameName = try? c.decodeIfPresent(String.self, forKey: .riotIdGameName)
        summonerName = try? c.decodeIfPresent(String.self, forKey: .summonerName)
        team = (try? c.decodeIfPresent(String.self, forKey: .team)) ?? ""
        level = (try? c.decodeIfPresent(Int.self, forKey: .level)) ?? 1
        isDead = (try? c.decodeIfPresent(Bool.self, forKey: .isDead)) ?? false
        respawnTimer = try? c.decodeIfPresent(Double.self, forKey: .respawnTimer)
        position = try? c.decodeIfPresent(String.self, forKey: .position)
        scores = (try? c.decodeIfPresent(Scores.self, forKey: .scores)) ?? Scores(kills: 0, deaths: 0, assists: 0, creepScore: 0)
        items = ((try? c.decodeIfPresent([Lossy<Item>].self, forKey: .items)) ?? []).compactMap(\.value)
    }

    private enum CodingKeys: String, CodingKey {
        case championName, riotId, riotIdGameName, summonerName, team, level, isDead, respawnTimer, position, scores, items
    }
}

struct LiveEvents: Decodable, Sendable {
    var Events: [LiveEvent]

    init(Events: [LiveEvent]) { self.Events = Events }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        Events = (try c.decodeIfPresent([Lossy<LiveEvent>].self, forKey: .Events) ?? []).compactMap(\.value)
    }

    private enum CodingKeys: String, CodingKey { case Events }
}

struct LiveEvent: Decodable, Sendable, Hashable {
    var EventID: Int
    var EventName: String
    var EventTime: Double
    var KillerName: String?
    var DragonType: String?
    var Stolen: String?
    var InhibKilled: String?
    var AcingTeam: String?
}

struct LiveGameStats: Decodable, Sendable {
    var gameTime: Double
}

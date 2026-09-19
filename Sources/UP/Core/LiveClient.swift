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
    struct Stats: Decodable, Sendable {
        var attackDamage: Double?, abilityPower: Double?, armor: Double?, magicResist: Double?
        var attackSpeed: Double?, moveSpeed: Double?, critChance: Double?, abilityHaste: Double?
        var lifeSteal: Double?, omnivamp: Double?, physicalLethality: Double?, magicPenetrationFlat: Double?
        var currentHealth: Double?, maxHealth: Double?, resourceValue: Double?, resourceMax: Double?
        var resourceType: String?, attackRange: Double?, healthRegenRate: Double?, tenacity: Double?
    }
    var riotId: String?
    var summonerName: String?
    var level: Int?
    var currentGold: Double?
    var championStats: Stats?
}

struct LivePlayer: Decodable, Sendable, Identifiable, Hashable {
    struct Scores: Decodable, Sendable, Hashable {
        var kills: Int
        var deaths: Int
        var assists: Int
        var creepScore: Int
        var wardScore: Double?

        init(kills: Int, deaths: Int, assists: Int, creepScore: Int, wardScore: Double?) {
            self.kills = kills; self.deaths = deaths; self.assists = assists; self.creepScore = creepScore; self.wardScore = wardScore
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kills = (try? c.decodeIfPresent(Int.self, forKey: .kills)) ?? 0
            deaths = (try? c.decodeIfPresent(Int.self, forKey: .deaths)) ?? 0
            assists = (try? c.decodeIfPresent(Int.self, forKey: .assists)) ?? 0
            creepScore = (try? c.decodeIfPresent(Int.self, forKey: .creepScore)) ?? 0
            wardScore = try? c.decodeIfPresent(Double.self, forKey: .wardScore)
        }

        private enum CodingKeys: String, CodingKey { case kills, deaths, assists, creepScore, wardScore }
    }
    struct Item: Decodable, Sendable, Hashable {
        var itemID: Int
        var count: Int?
        var slot: Int?
        var displayName: String?
    }
    struct Spell: Decodable, Sendable, Hashable { var displayName: String? }
    struct Spells: Decodable, Sendable, Hashable { var summonerSpellOne: Spell?; var summonerSpellTwo: Spell? }
    struct Runes: Decodable, Sendable, Hashable {
        struct Rune: Decodable, Sendable, Hashable { var id: Int?; var displayName: String? }
        var keystone: Rune?
    }

    var championName: String
    var riotId: String?
    var riotIdGameName: String?
    var riotIdTagLine: String?
    var summonerName: String?
    var team: String
    var level: Int
    var isDead: Bool
    var respawnTimer: Double?
    var position: String?
    var scores: Scores
    var items: [Item]
    var summonerSpells: Spells?
    var runes: Runes?

    var id: String { (riotId ?? summonerName ?? "") + championName }
    var name: String { riotIdGameName ?? riotId ?? summonerName ?? championName }

    init(championName: String, riotId: String?, riotIdGameName: String?, riotIdTagLine: String?, summonerName: String?,
         team: String, level: Int, isDead: Bool, respawnTimer: Double?, position: String?, scores: Scores,
         items: [Item], summonerSpells: Spells?, runes: Runes?) {
        self.championName = championName; self.riotId = riotId; self.riotIdGameName = riotIdGameName
        self.riotIdTagLine = riotIdTagLine; self.summonerName = summonerName; self.team = team; self.level = level
        self.isDead = isDead; self.respawnTimer = respawnTimer; self.position = position; self.scores = scores
        self.items = items; self.summonerSpells = summonerSpells; self.runes = runes
    }

    /// Missing optional data falls back to defaults so one odd entry never drops a real player.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        championName = try c.decode(String.self, forKey: .championName)
        riotId = try? c.decodeIfPresent(String.self, forKey: .riotId)
        riotIdGameName = try? c.decodeIfPresent(String.self, forKey: .riotIdGameName)
        riotIdTagLine = try? c.decodeIfPresent(String.self, forKey: .riotIdTagLine)
        summonerName = try? c.decodeIfPresent(String.self, forKey: .summonerName)
        team = (try? c.decodeIfPresent(String.self, forKey: .team)) ?? ""
        level = (try? c.decodeIfPresent(Int.self, forKey: .level)) ?? 1
        isDead = (try? c.decodeIfPresent(Bool.self, forKey: .isDead)) ?? false
        respawnTimer = try? c.decodeIfPresent(Double.self, forKey: .respawnTimer)
        position = try? c.decodeIfPresent(String.self, forKey: .position)
        scores = (try? c.decodeIfPresent(Scores.self, forKey: .scores)) ?? Scores(kills: 0, deaths: 0, assists: 0, creepScore: 0, wardScore: nil)
        items = ((try? c.decodeIfPresent([Lossy<Item>].self, forKey: .items)) ?? []).compactMap(\.value)
        summonerSpells = try? c.decodeIfPresent(Spells.self, forKey: .summonerSpells)
        runes = try? c.decodeIfPresent(Runes.self, forKey: .runes)
    }

    private enum CodingKeys: String, CodingKey {
        case championName, riotId, riotIdGameName, riotIdTagLine, summonerName, team, level, isDead, respawnTimer, position, scores, items, summonerSpells, runes
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
    var VictimName: String?
    var DragonType: String?
    var Stolen: String?
    var InhibKilled: String?
    var TurretKilled: String?
    var Assisters: [String]?
    var KillStreak: Int?
    var Acer: String?
    var AcingTeam: String?
}

struct LiveGameStats: Decodable, Sendable {
    var gameMode: String?
    var gameTime: Double
    var mapNumber: Int?
}

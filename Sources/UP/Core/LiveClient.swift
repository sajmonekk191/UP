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
}

struct LiveEvents: Decodable, Sendable {
    var Events: [LiveEvent]
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

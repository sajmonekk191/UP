import Foundation

// MARK: - Summoner / ranked / history

struct Summoner: Decodable, Hashable, Sendable {
    var puuid: String
    var summonerId: Int?
    var gameName: String?
    var tagLine: String?
    var summonerLevel: Int?
    var profileIconId: Int?

    var riotId: String {
        guard let gameName, !gameName.isEmpty else { return tr("Unknown player") }
        return tagLine.map { "\(gameName)#\($0)" } ?? gameName
    }
}

struct RankedQueue: Decodable, Hashable, Sendable {
    var tier: String?
    var division: String?
    var leaguePoints: Int?
    var wins: Int?
    var losses: Int?
    var previousSeasonEndTier: String?
    var previousSeasonEndDivision: String?

    var isRanked: Bool { !(tier ?? "").isEmpty && tier != "NONE" }

    var label: String {
        guard isRanked, let tier else { return "Unranked" }
        let short = ["IRON", "BRONZE", "SILVER", "GOLD", "PLATINUM", "EMERALD", "DIAMOND"].contains(tier)
        let name = tier.prefix(1) + tier.dropFirst().lowercased()
        return short ? "\(name) \(division ?? "") · \(leaguePoints ?? 0) LP" : "\(name) · \(leaguePoints ?? 0) LP"
    }

    var games: Int { (wins ?? 0) + (losses ?? 0) }
    var winRate: Double? { games > 0 ? Double(wins ?? 0) / Double(games) : nil }
}

struct RankedStats: Decodable, Sendable {
    var queueMap: [String: RankedQueue]?

    var solo: RankedQueue? { queueMap?["RANKED_SOLO_5x5"] }
    var flex: RankedQueue? { queueMap?["RANKED_FLEX_SR"] }
}

struct MatchHistoryResponse: Decodable, Sendable {
    struct Games: Decodable, Sendable { var games: [HistoryGame]? }
    var games: Games?
}

struct HistoryGame: Codable, Identifiable, Hashable, Sendable {
    var gameId: Int
    var gameCreation: Double?
    var gameDuration: Int?
    var gameMode: String?
    var gameType: String?
    var queueId: Int?
    var participants: [HistoryParticipant]?
    var participantIdentities: [ParticipantIdentity]?
    var teams: [HistoryTeam]?

    var id: Int { gameId }
    var me: HistoryParticipant? { participants?.first }
    var minutes: Double { max(Double(gameDuration ?? 0) / 60, 1) }

    func identity(for participantId: Int?) -> ParticipantIdentity.Player? {
        participantIdentities?.first { $0.participantId == participantId }?.player
    }
    var date: Date? { gameCreation.map { Date(timeIntervalSince1970: $0 / 1000) } }
    var isRemake: Bool { (gameDuration ?? 0) < 300 }
    var isCountable: Bool { !isRemake && gameType != "CUSTOM_GAME" && gameMode != "PRACTICETOOL" }
}

struct HistoryParticipant: Codable, Hashable, Sendable {
    struct Timeline: Codable, Hashable, Sendable { var lane: String?; var role: String? }
    var participantId: Int?
    var teamId: Int?
    var championId: Int
    var spell1Id: Int?
    var spell2Id: Int?
    var stats: HistoryStats
    var timeline: Timeline?

    /// Lane derived from Riot's lane/role pair.
    var lane: Lane? {
        switch (timeline?.lane, timeline?.role) {
        case ("TOP", _): .top
        case ("JUNGLE", _): .jungle
        case ("MIDDLE", _), ("MID", _): .middle
        case ("BOTTOM", "DUO_SUPPORT"), ("BOTTOM", "SUPPORT"): .utility
        case ("BOTTOM", _): .bottom
        default: nil
        }
    }
}

struct ParticipantIdentity: Codable, Hashable, Sendable {
    struct Player: Codable, Hashable, Sendable {
        var puuid: String?
        var gameName: String?
        var tagLine: String?
        var riotId: String { [gameName, tagLine].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "#") }
    }
    var participantId: Int
    var player: Player
}

struct HistoryTeam: Codable, Hashable, Sendable {
    struct Ban: Codable, Hashable, Sendable { var championId: Int }
    var teamId: Int
    var win: String?
    var bans: [Ban]?
    var baronKills: Int?
    var dragonKills: Int?
    var towerKills: Int?
    var riftHeraldKills: Int?
    var hordeKills: Int?
}

struct HistoryStats: Codable, Hashable, Sendable {
    var win: Bool?
    var kills: Int?
    var deaths: Int?
    var assists: Int?
    var champLevel: Int?
    var totalMinionsKilled: Int?
    var neutralMinionsKilled: Int?
    var goldEarned: Int?
    var totalDamageDealtToChampions: Int?
    var visionScore: Int?
    var totalDamageTaken: Int?
    var damageSelfMitigated: Int?
    var damageDealtToObjectives: Int?
    var largestKillingSpree: Int?
    var tripleKills: Int?, quadraKills: Int?, pentaKills: Int?
    var firstBloodKill: Bool?
    var turretKills: Int?
    var item0: Int?, item1: Int?, item2: Int?, item3: Int?, item4: Int?, item5: Int?, item6: Int?
    var perk0: Int?
    var perkSubStyle: Int?

    var items: [Int] { [item0, item1, item2, item3, item4, item5, item6].map { $0 ?? 0 } }
    var cs: Int { (totalMinionsKilled ?? 0) + (neutralMinionsKilled ?? 0) }
    var kda: Double { Double((kills ?? 0) + (assists ?? 0)) / Double(max(deaths ?? 0, 1)) }
}

struct RegionLocale: Decodable, Sendable {
    var webRegion: String?
}

struct ChampionMastery: Decodable, Hashable, Sendable {
    var championId: Int
    var championLevel: Int?
    var championPoints: Int?
}

struct Friend: Decodable, Hashable, Sendable {
    var gameName: String?
    var gameTag: String?
    var icon: Int?

    var riotId: String? {
        guard let gameName, !gameName.isEmpty, let gameTag, !gameTag.isEmpty else { return nil }
        return "\(gameName)#\(gameTag)"
    }
}

// MARK: - Gameflow / champ select

struct ReadyCheck: Decodable, Sendable {
    var state: String?
    var playerResponse: String?
}

/// Matchmaking of the queues the client runs through team builder, such as Swiftplay.
struct TeamBuilderMatchmaking: Decodable, Sendable {
    var readyCheck: ReadyCheck?
}

struct ChampSelectSession: Decodable, Sendable, Equatable {
    var localPlayerCellId: Int
    var myTeam: [ChampSelectPlayer]
    var theirTeam: [ChampSelectPlayer]?
    var actions: [[ChampSelectAction]]?
    var timer: ChampSelectTimer?
    var benchEnabled: Bool?
    var benchChampions: [BenchChampion]?
    var allowRerolling: Bool?
    var rerollsRemaining: Int?

    var me: ChampSelectPlayer? { myTeam.first { $0.cellId == localPlayerCellId } }

    var myActiveAction: ChampSelectAction? {
        actions?.joined().first { $0.actorCellId == localPlayerCellId && $0.isInProgress == true && $0.completed != true }
    }
}

struct ChampSelectPlayer: Decodable, Sendable, Hashable, Identifiable {
    var cellId: Int
    var championId: Int?
    var championPickIntent: Int?
    var assignedPosition: String?
    var puuid: String?
    var gameName: String?

    var id: Int { cellId }
    var displayedChampionId: Int { (championId ?? 0) != 0 ? championId! : (championPickIntent ?? 0) }
    var hasIdentity: Bool { !(puuid ?? "").isEmpty }
}

struct BenchChampion: Decodable, Sendable, Hashable {
    var championId: Int
    var isPriority: Bool?
}

struct ChampSelectAction: Decodable, Sendable, Hashable {
    var id: Int
    var actorCellId: Int
    var championId: Int?
    var completed: Bool?
    var isInProgress: Bool?
    var type: String?
}

struct ChampSelectTimer: Decodable, Sendable, Equatable {
    var adjustedTimeLeftInPhase: Double?
    var internalNowInEpochMs: Double?
}

struct GameflowSession: Decodable, Sendable {
    struct Map: Decodable, Sendable { var id: Int? }
    struct GameData: Decodable, Sendable {
        struct Queue: Decodable, Sendable { var gameMode: String? }
        var queue: Queue?
        var teamOne: [GameTeamPlayer]?
        var teamTwo: [GameTeamPlayer]?
    }
    var map: Map?
    var gameData: GameData?
}

struct GameTeamPlayer: Decodable, Sendable, Hashable {
    var puuid: String?
    var championId: Int?
}

// MARK: - Perks

struct PerkPage: Decodable, Identifiable, Sendable, Hashable {
    var id: Int
    var name: String
    var isDeletable: Bool?
    var isEditable: Bool?
    var isTemporary: Bool?
    var current: Bool?
    var primaryStyleId: Int?
    var subStyleId: Int?
    var selectedPerkIds: [Int]?
}

struct PerkInventory: Decodable, Sendable {
    var canAddCustomPage: Bool?
}

struct RecommendedPage: Decodable, Sendable, Hashable {
    struct Perk: Decodable, Sendable, Hashable { var id: Int; var name: String? }
    var perks: [Perk]
    var primaryPerkStyleId: Int
    var secondaryPerkStyleId: Int
    var summonerSpellIds: [Int]?
    var position: String?
    var keystone: Perk?
}

/// Rune page ready to be written into the client, independent of its source.
struct RuneSetup: Hashable, Sendable, Identifiable {
    var title: String
    var primaryStyleId: Int
    var subStyleId: Int
    var perkIds: [Int]
    var spells: [Int]?
    var winRate: Double?
    var games: Int?
    var source: String

    var id: String { "\(source)-\(perkIds.map(String.init).joined(separator: ","))" }
}

// MARK: - Static game data (from the client's bundled assets)

struct ChampionSummary: Decodable, Sendable, Hashable {
    var id: Int
    var name: String
    var alias: String
    var roles: [String]?
}

struct PerkInfo: Decodable, Sendable {
    var id: Int
    var name: String
    var iconPath: String?
    var shortDesc: String?
    var longDesc: String?
}

struct PerkStyleList: Decodable, Sendable {
    struct Style: Decodable, Sendable { var id: Int; var name: String; var iconPath: String? }
    var styles: [Style]
}

struct ItemInfo: Decodable, Sendable {
    var id: Int
    var name: String
    var description: String?
    var categories: [String]?
    var priceTotal: Int?
    var iconPath: String?
    var from: [Int]?
    var to: [Int]?
}

struct AugmentInfo: Decodable, Sendable {
    var id: Int
    var nameTRA: String?
    var augmentSmallIconPath: String?
}

struct SummonerSpellInfo: Decodable, Sendable {
    var id: Int
    var name: String
    var description: String?
    var iconPath: String?
}

// MARK: - Positions

enum Lane: String, CaseIterable, Identifiable, Sendable {
    case top = "TOP", jungle = "JUNGLE", middle = "MIDDLE", bottom = "BOTTOM", utility = "UTILITY"

    var id: String { rawValue }

    init?(clientPosition: String?) {
        switch clientPosition?.lowercased() {
        case "top": self = .top
        case "jungle": self = .jungle
        case "middle", "mid": self = .middle
        case "bottom", "adc", "bot": self = .bottom
        case "utility", "support": self = .utility
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .top: "Top"
        case .jungle: "Jungle"
        case .middle: "Mid"
        case .bottom: "ADC"
        case .utility: "Support"
        }
    }

    var opggName: String {
        switch self {
        case .top: "top"
        case .jungle: "jungle"
        case .middle: "mid"
        case .bottom: "adc"
        case .utility: "support"
        }
    }

    var symbol: String {
        switch self {
        case .top: "arrow.up.left"
        case .jungle: "leaf"
        case .middle: "arrow.up.right"
        case .bottom: "arrow.down.right"
        case .utility: "cross.case"
        }
    }
}

// MARK: - Champion details (client game data)

struct ChampionDetail: Decodable, Sendable {
    struct Tactical: Decodable, Sendable { var difficulty: Int?; var damageType: String?; var attackType: String? }
    struct Playstyle: Decodable, Sendable {
        var damage: Int?; var durability: Int?; var crowdControl: Int?; var mobility: Int?; var utility: Int?
    }
    struct Passive: Decodable, Sendable { var name: String; var abilityIconPath: String?; var description: String? }
    struct Spell: Decodable, Sendable, Identifiable {
        var spellKey: String
        var name: String
        var abilityIconPath: String?
        var description: String?
        var cooldownCoefficients: [Double]?
        var costCoefficients: [Double]?
        var maxLevel: Int?
        var id: String { spellKey }
    }
    struct Skin: Decodable, Sendable { var id: Int?; var name: String?; var splashPath: String?; var uncenteredSplashPath: String?; var tilePath: String? }

    var id: Int
    var name: String
    var title: String?
    var roles: [String]?
    var tacticalInfo: Tactical?
    var playstyleInfo: Playstyle?
    var passive: Passive?
    var spells: [Spell]
    var skins: [Skin]?

    var splashPath: String? { skins?.first?.splashPath ?? skins?.first?.uncenteredSplashPath }
    var tilePath: String? { skins?.first?.tilePath }
}

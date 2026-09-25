import Foundation

/// Aggregated build statistics for one champion in one role.
struct ChampionBuild: Sendable {
    struct Stat: Sendable, Hashable, Identifiable {
        var ids: [Int]
        var play: Int
        var win: Int

        var id: String { ids.map(String.init).joined(separator: "-") }
        var winRate: Double { play > 0 ? Double(win) / Double(play) : 0 }
    }
    struct SkillOrder: Sendable, Hashable {
        var priority: [String]
        var order: [String]
        var winRate: Double
        var pickRate: Double

        /// Levels 16 to 18, which follow from the earlier ones, added to the order op.gg stops at.
        static func complete(_ order: [String], priority: [String]) -> [String] {
            var order = order
            var taken = order.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
            let basics = priority.filter { $0 != "R" }
            guard basics.count == 3, taken["R"] != nil else { return order }
            while order.count < 18 {
                let level = order.count + 1
                let next = level == 16 && (taken["R"] ?? 0) < 3 ? "R" : basics.first { (taken[$0] ?? 0) < 5 }
                guard let next else { break }
                order.append(next)
                taken[next, default: 0] += 1
            }
            return order
        }

        /// Ability to put the next point in, or nil when none is unspent: the recommended order while the game allows it, else the max priority.
        func nextPoint(level: Int, spent levels: [String: Int]) -> String? {
            let spent = ["Q", "W", "E", "R"].reduce(0) { $0 + (levels[$1] ?? 0) }
            guard spent < level else { return nil }
            func allowed(_ key: String) -> Bool {
                let points = levels[key] ?? 0
                return key == "R" ? points < [6, 11, 16].filter { $0 <= level }.count : points < min(5, (level + 1) / 2)
            }
            if order.indices.contains(spent), allowed(order[spent]) { return order[spent] }
            return (["R"] + priority.filter { $0 != "R" }).first(where: allowed)
        }
    }
    struct Matchup: Sendable, Hashable, Identifiable {
        var championId: Int
        var play: Int
        var winRate: Double
        var id: Int { championId }
    }
    /// Arena augment with its rarity: 1 silver, 4 gold, 8 prismatic.
    struct Augment: Sendable, Hashable, Identifiable {
        var id: Int
        var rarity: Int
        var play: Int
        var winRate: Double
    }

    var championId: Int
    var lane: Lane?
    var winRate: Double?
    var pickRate: Double?
    var banRate: Double?
    var tier: Int?
    var runes: [RuneSetup]
    var spells: [Stat]
    var starterItems: [Stat]
    var coreItems: [Stat]
    var boots: [Stat]
    var lastItems: [Stat]
    var skillOrder: SkillOrder?
    var counters: [Matchup]
    var availableLanes: [Lane]
    var gameLengths: [(minute: Int, winRate: Double)] = []
    var patchTrend: [(patch: String, winRate: Double, rank: Int)] = []
    var laneShares: [(lane: Lane, share: Double)] = []
    var kda: Double?
    var rank: Int?
    var augments: [Augment] = []
    var prismItems: [Stat] = []
    var duoPartners: [Matchup] = []
    var firstPlaceRate: Double?
    var averagePlace: Double?
    var patch: String?
}

struct TierListEntry: Sendable, Identifiable, Hashable {
    var championId: Int
    var lane: Lane?
    var tier: Int
    var rank: Int
    var winRate: Double
    var pickRate: Double
    var banRate: Double
    var play: Int
    var previousRank: Int?
    var id: String { "\(championId)-\(lane?.rawValue ?? "-")" }
    var rankChange: Int { previousRank.map { $0 - rank } ?? 0 }
}

/// One op.gg tier list with the patch its statistics come from.
struct TierList: Sendable {
    var entries: [TierListEntry]
    var patch: String?
}

/// Which op.gg tier list to load: mode, Solo/Duo or Flex, server and rank bracket.
struct TierListQuery: Hashable, Sendable {
    var mode: QueueMode = .ranked
    var flex = false
    var region: Region?
    var rank: EloTier = .emeraldPlus

    /// The same query without the options op.gg ignores for its mode.
    var normalized: TierListQuery { TierListQuery(mode: mode, flex: mode == .ranked && flex, region: region, rank: mode == .arena ? .emeraldPlus : rank) }
}

enum QueueMode: String, CaseIterable, Identifiable, Sendable {
    case ranked, aram, arena, urf
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ranked: "Summoner's Rift"
        case .aram: "ARAM"
        case .arena: tr("Arena")
        case .urf: "URF"
        }
    }
    var mapId: Int {
        switch self {
        case .ranked, .urf: 11
        case .aram: 12
        case .arena: 30
        }
    }
}

enum EloTier: String, CaseIterable, Identifiable, Sendable {
    case all, goldPlus = "gold_plus", platinumPlus = "platinum_plus", emeraldPlus = "emerald_plus", diamondPlus = "diamond_plus", masterPlus = "master_plus"
    case iron, bronze, silver, gold, platinum, emerald, diamond, master, grandmaster, challenger

    /// Brackets whose builds champ select compares.
    static let buildBrackets: [EloTier] = [.emeraldPlus, .masterPlus, .challenger]
    static let brackets: [EloTier] = [.all, .goldPlus, .platinumPlus, .emeraldPlus, .diamondPlus, .masterPlus]
    static let singleTiers: [EloTier] = [.iron, .bronze, .silver, .gold, .platinum, .emerald, .diamond, .master, .grandmaster, .challenger]

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: tr("All ranks")
        case .goldPlus: "Gold+"
        case .platinumPlus: "Platinum+"
        case .emeraldPlus: "Emerald+"
        case .diamondPlus: "Diamond+"
        case .masterPlus: "Master+"
        default: rawValue.capitalized
        }
    }
}

/// Fetches build stats from op.gg's public champion API and Riot's in-client recommendations.
enum BuildService {
    private static let api = "https://lol-api-champion.op.gg/api"
    private static let base = "\(api)/global/champions"

    static func opggBuild(championId: Int, lane: Lane?, mode: QueueMode, tier: EloTier = .emeraldPlus) async throws -> ChampionBuild {
        var lane = lane
        if mode == .ranked, lane == nil { lane = await mainLane(championId) }
        let key = "\(championId)-\(lane?.rawValue ?? "-")-\(mode.rawValue)-\(tier.rawValue)"
        return try await BuildCache.shared.build(key) { [lane] in
            try await fetchBuild(championId: championId, lane: lane, mode: mode, tier: tier)
        }
    }

    private static func fetchBuild(championId: Int, lane: Lane?, mode: QueueMode, tier: EloTier) async throws -> ChampionBuild {
        let path = switch mode {
        case .ranked: "\(championId)/\(lane?.opggName ?? "mid")?tier=\(tier.rawValue)"
        case .aram, .urf: "\(championId)/none?tier=\(tier.rawValue)"
        case .arena: "\(championId)"
        }
        let url = URL(string: "\(base)/\(mode.rawValue)/\(path)")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw BuildError.unavailable(tr("op.gg returned no data (HTTP %d)", (response as? HTTPURLResponse)?.statusCode ?? 0))
        }
        let root = try jsonDecoder.decode(OpggRoot.self, from: data)
        var build = root.data.build(championId: championId, requestedLane: lane)
        build.patch = root.meta?.version
        if mode != .ranked { build.gameLengths.removeAll { $0.minute >= 35 } }
        guard !build.runes.isEmpty || !build.augments.isEmpty else { throw BuildError.unavailable(tr("op.gg has no data for this champion")) }
        if tier != .emeraldPlus {
            build.runes = build.runes.map { var r = $0; r.source = tier.title; return r }
        }
        return build
    }

    /// Most played lane of a champion according to the cached tier list.
    static func mainLane(_ championId: Int) async -> Lane? {
        let entries = (try? await tierList()) ?? []
        return entries.filter { $0.championId == championId }.max { $0.play < $1.play }?.lane
    }

    static func tierList(_ mode: QueueMode = .ranked) async throws -> [TierListEntry] {
        try await tierList(for: TierListQuery(mode: mode)).entries
    }

    static func tierList(for query: TierListQuery) async throws -> TierList {
        try await TierListCache.shared.list(query.normalized)
    }

    /// Patch of op.gg's global ranked statistics, which follow the live game.
    static func currentPatch() async -> String? {
        try? await tierList(for: TierListQuery()).patch
    }

    /// Whether statistics from `patch` are two or more patches behind `current`, as for a mode out of rotation.
    static func isOutdated(_ patch: String?, current: String?) -> Bool {
        let old = (patch ?? "").split(separator: ".").compactMap { Int($0) }, now = (current ?? "").split(separator: ".").compactMap { Int($0) }
        guard old.count >= 2, now.count >= 2 else { return false }
        return now[0] > old[0] || now[1] - old[1] >= 2
    }

    fileprivate static func fetchTierList(_ query: TierListQuery) async throws -> TierList {
        let path = query.mode == .ranked ? (query.flex ? "flex" : "ranked") : query.mode.rawValue
        let tier = query.mode == .arena ? "" : "?tier=\(query.rank.rawValue)"
        let url = URL(string: "\(api)/\(query.region?.rawValue ?? "global")/champions/\(path)\(tier)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw BuildError.unavailable(tr("op.gg returned no data (HTTP %d)", (response as? HTTPURLResponse)?.statusCode ?? 0))
        }
        let root = try jsonDecoder.decode(OpggTierRoot.self, from: data)
        guard query.mode == .ranked else {
            return TierList(entries: root.data.compactMap { $0.average_stats?.tierEntry(championId: $0.id, lane: nil) }, patch: root.meta?.version)
        }
        let entries = root.data.flatMap { champ in
            (champ.positions ?? []).compactMap { pos in
                Lane(clientPosition: pos.name).flatMap { pos.stats?.tierEntry(championId: champ.id, lane: $0) }
            }
        }
        return TierList(entries: entries, patch: root.meta?.version)
    }

    static func riotRecommended(client: LCUClient, championId: Int, lane: Lane?, mapId: Int) async throws -> [RuneSetup] {
        let position = mapId == 12 ? "NONE" : (lane?.rawValue ?? "NONE")
        let pages: [RecommendedPage] = try await client.get(
            "/lol-perks/v1/recommended-pages/champion/\(championId)/position/\(position)/map/\(mapId)")
        return pages.map { page in
            RuneSetup(title: page.keystone?.name ?? "Riot",
                      primaryStyleId: page.primaryPerkStyleId, subStyleId: page.secondaryPerkStyleId,
                      perkIds: page.perks.map(\.id), spells: page.summonerSpellIds,
                      winRate: nil, games: nil, source: "Riot")
        }
    }
}

enum BuildError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? { if case let .unavailable(message) = self { return message }; return nil }
}

/// Five-minute cache of op.gg champion builds; parallel requests for the same build share one download.
actor BuildCache {
    static let shared = BuildCache()
    private var store: [String: (date: Date, build: ChampionBuild)] = [:]
    private var pending: [String: Task<ChampionBuild, Error>] = [:]

    func build(_ key: String, fetch: @escaping @Sendable () async throws -> ChampionBuild) async throws -> ChampionBuild {
        if let hit = store[key], Date().timeIntervalSince(hit.date) < 300 { return hit.build }
        if let task = pending[key] { return try await task.value }
        let task = Task { try await fetch() }
        pending[key] = task
        defer { pending[key] = nil }
        let build = try await task.value
        store = store.filter { Date().timeIntervalSince($0.value.date) < 300 }
        store[key] = (Date(), build)
        return build
    }
}

/// Keeps the op.gg tier list for ten minutes so lane lookups stay cheap; parallel callers share one download.
actor TierListCache {
    static let shared = TierListCache()
    private var cached: [TierListQuery: (date: Date, list: TierList)] = [:]
    private var pending: [TierListQuery: Task<TierList, Error>] = [:]

    func list(_ query: TierListQuery) async throws -> TierList {
        if let hit = cached[query], Date().timeIntervalSince(hit.date) < 600 { return hit.list }
        if let task = pending[query] { return try await task.value }
        let task = Task { try await BuildService.fetchTierList(query) }
        pending[query] = task
        defer { pending[query] = nil }
        let list = try await task.value
        cached = cached.filter { Date().timeIntervalSince($0.value.date) < 600 }
        cached[query] = (Date(), list)
        return list
    }
}

// MARK: - op.gg payload

private struct OpggMeta: Decodable { var version: String? }
private struct OpggRoot: Decodable { var data: OpggChampion; var meta: OpggMeta? }
private struct OpggTierRoot: Decodable { var data: [OpggSummary]; var meta: OpggMeta? }

private struct OpggTierData: Decodable { var tier: Int?; var rank: Int?; var rank_prev_patch: Int? }
private struct OpggGameLength: Decodable { var game_length: Int; var rate: Double? }
private struct OpggTrends: Decodable {
    struct Point: Decodable { var version: String; var rate: Double?; var rank: Int? }
    var win: [Point]?
}
private struct OpggStats: Decodable {
    var play: Int?
    var win: Int?
    var first_place: Int?
    var total_place: Int?
    var kills: Int?
    var deaths: Int?
    var assists: Int?
    var kda: Double?
    var role_rate: Double?
    var win_rate: Double?
    var pick_rate: Double?
    var ban_rate: Double?
    var tier_data: OpggTierData?
    var tier: Int?

    /// Tier list row, with the win rate worked out from wins where op.gg leaves it out.
    func tierEntry(championId: Int, lane: Lane?) -> TierListEntry? {
        guard let tierData = tier_data else { return nil }
        return TierListEntry(championId: championId, lane: lane, tier: tierData.tier ?? 5, rank: tierData.rank ?? 999,
                             winRate: win_rate ?? Double(win ?? 0) / Double(max(play ?? 0, 1)), pickRate: pick_rate ?? 0,
                             banRate: ban_rate ?? 0, play: play ?? 0, previousRank: tierData.rank_prev_patch)
    }
}
private struct OpggPosition: Decodable { var name: String; var stats: OpggStats? }
private struct OpggSummary: Decodable {
    var id: Int
    var average_stats: OpggStats?
    var positions: [OpggPosition]?
}
private struct OpggStat: Decodable {
    var ids: [Int]?
    var play: Int?
    var win: Int?

    var model: ChampionBuild.Stat? {
        guard let ids, !ids.isEmpty else { return nil }
        return .init(ids: ids, play: play ?? 0, win: win ?? 0)
    }
}
private struct OpggRune: Decodable {
    var primary_page_id: Int
    var primary_rune_ids: [Int]
    var secondary_page_id: Int
    var secondary_rune_ids: [Int]
    var stat_mod_ids: [Int]
    var play: Int?
    var win: Int?
}
private struct OpggSkill: Decodable {
    struct Build: Decodable { var order: [String]; var play: Int?; var win: Int? }
    var ids: [String]
    var pick_rate: Double?
    var builds: [Build]?
}
private struct OpggCounter: Decodable { var champion_id: Int; var play: Int?; var win: Int? }
private struct OpggAugmentGroup: Decodable {
    struct Augment: Decodable { var id: Int; var play: Int?; var win: Int? }
    var rarity: Int
    var augments: [Augment]?
}
private struct OpggChampion: Decodable {
    var summary: OpggSummary?
    var summoner_spells: [OpggStat]?
    var core_items: [OpggStat]?
    var boots: [OpggStat]?
    var starter_items: [OpggStat]?
    var last_items: [OpggStat]?
    var runes: [OpggRune]?
    var skill_masteries: [OpggSkill]?
    var counters: [OpggCounter]?
    var synergies: [OpggCounter]?
    var prism_items: [OpggStat]?
    var augment_group: [OpggAugmentGroup]?
    var game_lengths: [OpggGameLength]?
    var trends: OpggTrends?

    func build(championId: Int, requestedLane: Lane?) -> ChampionBuild {
        let lanes = (summary?.positions ?? []).compactMap { Lane(clientPosition: $0.name) }
        let laneStats = summary?.positions?.first { Lane(clientPosition: $0.name) == requestedLane }?.stats
        let stats = laneStats ?? summary?.average_stats

        let runeSetups = (runes ?? []).prefix(4).map { rune in
            RuneSetup(title: "op.gg", primaryStyleId: rune.primary_page_id, subStyleId: rune.secondary_page_id,
                      perkIds: rune.primary_rune_ids + rune.secondary_rune_ids + rune.stat_mod_ids,
                      spells: summoner_spells?.first?.ids,
                      winRate: (rune.play ?? 0) > 0 ? Double(rune.win ?? 0) / Double(rune.play!) : nil,
                      games: rune.play, source: "op.gg")
        }

        let skill = skill_masteries?.first.flatMap { mastery -> ChampionBuild.SkillOrder? in
            guard let build = mastery.builds?.first else { return nil }
            let win = Double(build.win ?? 0) / Double(max(build.play ?? 1, 1))
            return .init(priority: mastery.ids, order: ChampionBuild.SkillOrder.complete(build.order, priority: mastery.ids),
                         winRate: win, pickRate: mastery.pick_rate ?? 0)
        }

        let matchups = (counters ?? []).compactMap { c -> ChampionBuild.Matchup? in
            guard let play = c.play, play >= 50 else { return nil }
            return .init(championId: c.champion_id, play: play, winRate: Double(c.win ?? 0) / Double(play))
        }
        let games = Double(max(stats?.play ?? 0, 1))

        var result = ChampionBuild(
            championId: championId, lane: lanes.contains { $0 == requestedLane } ? requestedLane : lanes.first,
            winRate: stats?.win_rate ?? stats?.win.map { Double($0) / games }, pickRate: stats?.pick_rate, banRate: stats?.ban_rate,
            tier: stats?.tier_data?.tier ?? stats?.tier,
            runes: runeSetups,
            spells: (summoner_spells ?? []).compactMap(\.model),
            starterItems: (starter_items ?? []).compactMap(\.model),
            coreItems: (core_items ?? []).compactMap(\.model),
            boots: (boots ?? []).compactMap(\.model),
            lastItems: (last_items ?? []).compactMap(\.model),
            skillOrder: skill,
            counters: matchups,
            availableLanes: lanes)
        result.gameLengths = (game_lengths ?? []).compactMap { length in length.rate.map { (length.game_length, $0) } }
        result.patchTrend = (trends?.win ?? []).prefix(10).reversed().compactMap { point in point.rate.map { (point.version, $0, point.rank ?? 0) } }
        result.laneShares = (summary?.positions ?? []).compactMap { pos in
            Lane(clientPosition: pos.name).map { ($0, pos.stats?.role_rate ?? 0) }
        }
        let takedowns = Double((stats?.kills ?? 0) + (stats?.assists ?? 0))
        result.kda = stats?.kda ?? stats?.deaths.map { takedowns / Double(max($0, 1)) }
        result.rank = stats?.tier_data?.rank
        result.augments = (augment_group ?? []).flatMap { group in
            (group.augments ?? []).map { ChampionBuild.Augment(id: $0.id, rarity: group.rarity, play: $0.play ?? 0, winRate: Double($0.win ?? 0) / Double(max($0.play ?? 0, 1))) }
        }
        result.prismItems = (prism_items ?? []).compactMap(\.model)
        result.duoPartners = (synergies ?? []).compactMap { c -> ChampionBuild.Matchup? in
            guard let play = c.play, play >= 50 else { return nil }
            return .init(championId: c.champion_id, play: play, winRate: Double(c.win ?? 0) / Double(play))
        }
        result.firstPlaceRate = stats?.first_place.map { Double($0) / games }
        result.averagePlace = stats?.total_place.map { Double($0) / games }
        return result
    }
}

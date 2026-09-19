import Foundation

/// Aggregated build statistics for one champion in one role.
struct ChampionBuild: Sendable {
    struct Stat: Sendable, Hashable, Identifiable {
        var ids: [Int]
        var play: Int
        var win: Int
        var pickRate: Double?

        var id: String { ids.map(String.init).joined(separator: "-") }
        var winRate: Double { play > 0 ? Double(win) / Double(play) : 0 }
    }
    struct SkillOrder: Sendable, Hashable {
        var priority: [String]
        var order: [String]
        var winRate: Double
        var pickRate: Double
    }
    struct Matchup: Sendable, Hashable, Identifiable {
        var championId: Int
        var play: Int
        var winRate: Double
        var id: Int { championId }
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
    var previousRank: Int?
}

struct TierListEntry: Sendable, Identifiable, Hashable {
    var championId: Int
    var lane: Lane
    var tier: Int
    var rank: Int
    var winRate: Double
    var pickRate: Double
    var banRate: Double
    var play: Int
    var previousRank: Int?
    var id: String { "\(championId)-\(lane.rawValue)" }
    var rankChange: Int { previousRank.map { $0 - rank } ?? 0 }
}

enum QueueMode: String, CaseIterable, Identifiable, Sendable {
    case ranked, aram
    var id: String { rawValue }
    var title: String { self == .ranked ? "Summoner's Rift" : "ARAM" }
    var mapId: Int { self == .ranked ? 11 : 12 }
}

enum EloTier: String, CaseIterable, Identifiable, Sendable {
    case emeraldPlus = "emerald_plus", masterPlus = "master_plus", challenger

    var id: String { rawValue }
    var title: String {
        switch self {
        case .emeraldPlus: "Emerald+"
        case .masterPlus: "Master+"
        case .challenger: "Challenger"
        }
    }
}

/// Fetches build stats from op.gg's public champion API and Riot's in-client recommendations.
enum BuildService {
    private static let base = "https://lol-api-champion.op.gg/api/global/champions"

    static func opggBuild(championId: Int, lane: Lane?, mode: QueueMode, tier: EloTier = .emeraldPlus) async throws -> ChampionBuild {
        var lane = lane
        if mode == .ranked, lane == nil { lane = await mainLane(championId) }
        let key = "\(championId)-\(lane?.rawValue ?? "-")-\(mode.rawValue)-\(tier.rawValue)"
        if let cached = await BuildCache.shared.get(key) { return cached }
        let position = mode == .aram ? "none" : (lane?.opggName ?? "mid")
        let url = URL(string: "\(base)/\(mode.rawValue)/\(championId)/\(position)?tier=\(tier.rawValue)")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw BuildError.unavailable(tr("op.gg returned no data (HTTP %d)", (response as? HTTPURLResponse)?.statusCode ?? 0))
        }
        var build = try jsonDecoder.decode(OpggRoot.self, from: data).data.build(championId: championId, requestedLane: lane)
        guard !build.runes.isEmpty else { throw BuildError.unavailable(tr("op.gg has no data for this champion")) }
        if tier != .emeraldPlus {
            build.runes = build.runes.map { var r = $0; r.source = tier.title; return r }
        }
        await BuildCache.shared.set(key, build)
        return build
    }

    /// Most played lane of a champion according to the cached tier list.
    static func mainLane(_ championId: Int) async -> Lane? {
        let entries = (try? await TierListCache.shared.entries()) ?? []
        return entries.filter { $0.championId == championId }.max { $0.play < $1.play }?.lane
    }

    static func tierList() async throws -> [TierListEntry] {
        try await TierListCache.shared.entries()
    }

    fileprivate static func fetchTierList() async throws -> [TierListEntry] {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "\(base)/ranked")!)
        let list = try jsonDecoder.decode(OpggTierRoot.self, from: data).data
        return list.flatMap { champ in
            (champ.positions ?? []).compactMap { pos -> TierListEntry? in
                guard let lane = Lane(clientPosition: pos.name), let s = pos.stats, let tier = s.tier_data else { return nil }
                return TierListEntry(championId: champ.id, lane: lane, tier: tier.tier ?? 5, rank: tier.rank ?? 999,
                                     winRate: s.win_rate ?? 0, pickRate: s.pick_rate ?? 0,
                                     banRate: s.ban_rate ?? 0, play: s.play ?? 0, previousRank: tier.rank_prev_patch)
            }
        }
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

/// Five-minute cache of op.gg champion builds.
actor BuildCache {
    static let shared = BuildCache()
    private var store: [String: (date: Date, build: ChampionBuild)] = [:]

    func get(_ key: String) -> ChampionBuild? {
        guard let hit = store[key], Date().timeIntervalSince(hit.date) < 300 else { return nil }
        return hit.build
    }

    func set(_ key: String, _ build: ChampionBuild) { store[key] = (Date(), build) }
}

/// Keeps the op.gg tier list for ten minutes so lane lookups stay cheap.
actor TierListCache {
    static let shared = TierListCache()
    private var cached: (date: Date, entries: [TierListEntry])?

    func entries() async throws -> [TierListEntry] {
        if let cached, Date().timeIntervalSince(cached.date) < 600 { return cached.entries }
        let entries = try await BuildService.fetchTierList()
        cached = (Date(), entries)
        return entries
    }
}

// MARK: - op.gg payload

private struct OpggRoot: Decodable { var data: OpggChampion }
private struct OpggTierRoot: Decodable { var data: [OpggSummary] }

private struct OpggTierData: Decodable { var tier: Int?; var rank: Int?; var rank_prev_patch: Int? }
private struct OpggGameLength: Decodable { var game_length: Int; var rate: Double }
private struct OpggTrends: Decodable {
    struct Point: Decodable { var version: String; var rate: Double; var rank: Int? }
    var win: [Point]?
}
private struct OpggStats: Decodable {
    var play: Int?
    var kda: Double?
    var role_rate: Double?
    var win_rate: Double?
    var pick_rate: Double?
    var ban_rate: Double?
    var tier_data: OpggTierData?
    var tier: Int?
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
    var pick_rate: Double?

    var model: ChampionBuild.Stat? {
        guard let ids, !ids.isEmpty else { return nil }
        return .init(ids: ids, play: play ?? 0, win: win ?? 0, pickRate: pick_rate)
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
    struct Build: Decodable { var order: [String]; var play: Int?; var win: Int?; var pick_rate: Double? }
    var ids: [String]
    var play: Int?
    var win: Int?
    var pick_rate: Double?
    var builds: [Build]?
}
private struct OpggCounter: Decodable { var champion_id: Int; var play: Int?; var win: Int? }
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
            return .init(priority: mastery.ids, order: build.order, winRate: win, pickRate: mastery.pick_rate ?? 0)
        }

        let matchups = (counters ?? []).compactMap { c -> ChampionBuild.Matchup? in
            guard let play = c.play, play >= 50 else { return nil }
            return .init(championId: c.champion_id, play: play, winRate: Double(c.win ?? 0) / Double(play))
        }

        var result = ChampionBuild(
            championId: championId, lane: lanes.contains { $0 == requestedLane } ? requestedLane : lanes.first,
            winRate: stats?.win_rate, pickRate: stats?.pick_rate, banRate: stats?.ban_rate,
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
        result.gameLengths = (game_lengths ?? []).map { ($0.game_length, $0.rate) }
        result.patchTrend = (trends?.win ?? []).prefix(10).reversed().map { ($0.version, $0.rate, $0.rank ?? 0) }
        result.laneShares = (summary?.positions ?? []).compactMap { pos in
            Lane(clientPosition: pos.name).map { ($0, pos.stats?.role_rate ?? 0) }
        }
        result.kda = stats?.kda
        result.rank = stats?.tier_data?.rank
        result.previousRank = stats?.tier_data?.rank_prev_patch
        return result
    }
}

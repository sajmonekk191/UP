import Foundation

/// Which champions to play in one role: your own picks rated against the current tier list, and strong ones worth learning.
struct ChampionPool {
    struct Pick: Identifiable, Hashable {
        var championId: Int
        var entry: TierListEntry?
        var games: Int
        var winRate: Double?
        var mastery: Int
        var sharesClass = false
        var id: Int { championId }
    }

    var played: [Pick] = []
    var toLearn: [Pick] = []
    var weak: [Pick] { played.filter { ($0.entry?.tier ?? 0) >= 4 } }

    init(lane: Lane, profile: PlayerProfile, masteries: [ChampionMastery], tierList: [TierListEntry], champions: [Int: ChampionSummary]) {
        let entries = Dictionary(tierList.filter { $0.lane == lane }.map { ($0.championId, $0) }) { first, _ in first }
        var records: [Int: (games: Int, wins: Int)] = [:]
        for game in profile.recentGames where game.me?.lane == lane {
            guard let me = game.me else { continue }
            records[me.championId, default: (0, 0)].games += 1
            if me.stats.win == true { records[me.championId, default: (0, 0)].wins += 1 }
        }
        let points = Dictionary(masteries.map { ($0.championId, $0.championPoints ?? 0) }) { first, _ in first }
        let recent = records.keys.sorted { records[$0]!.games > records[$1]!.games }
        let comfortable = masteries.prefix(15).map(\.championId).filter { (entries[$0]?.pickRate ?? 0) >= 0.005 }
        var seen = Set<Int>()
        let pool = (recent + comfortable).filter { seen.insert($0).inserted }.prefix(6)

        played = pool.map { id in
            Pick(championId: id, entry: entries[id], games: records[id]?.games ?? 0,
                 winRate: records[id].map { Double($0.wins) / Double($0.games) }, mastery: points[id] ?? 0)
        }
        let classes = Set(pool.flatMap { champions[$0]?.roles ?? [] })
        toLearn = entries.values
            .filter { !pool.contains($0.championId) && $0.tier <= 2 && $0.pickRate >= 0.01 && (points[$0.championId] ?? 0) < 30_000 }
            .map { entry in
                Pick(championId: entry.championId, entry: entry, games: 0, winRate: nil, mastery: points[entry.championId] ?? 0,
                     sharesClass: !classes.isDisjoint(with: champions[entry.championId]?.roles ?? []))
            }
            .sorted { ($0.entry?.rank ?? 999) - ($0.sharesClass ? 8 : 0) < ($1.entry?.rank ?? 999) - ($1.sharesClass ? 8 : 0) }
            .prefix(4).map { $0 }
    }
}

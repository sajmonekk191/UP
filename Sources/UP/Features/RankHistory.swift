import Foundation

/// One reading of a ranked queue, stored whenever the signed-in player's rank or record changes.
struct RankSnapshot: Codable, Hashable, Sendable {
    var date: Date
    var tier: String
    var division: String?
    var leaguePoints: Int
    var wins: Int
    var losses: Int

    private static let tiers = ["IRON", "BRONZE", "SILVER", "GOLD", "PLATINUM", "EMERALD", "DIAMOND"]
    private static let divisions = ["IV", "III", "II", "I"]

    /// Position on a single ladder: 400 per tier and 100 per division below Master, where LP keeps counting.
    var score: Int {
        guard let index = Self.tiers.firstIndex(of: tier) else { return 2800 + leaguePoints }
        return index * 400 + (Self.divisions.firstIndex(of: division ?? "") ?? 0) * 100 + leaguePoints
    }

    var label: String {
        let name = tier.prefix(1) + tier.dropFirst().lowercased()
        return Self.tiers.contains(tier) ? "\(name) \(division ?? "") · \(leaguePoints) LP" : "\(name) · \(leaguePoints) LP"
    }

    /// Short rank name for a ladder position, such as "Gold II" or "Master+ 120".
    static func label(for score: Int) -> String {
        guard score < 2800 else { return "Master+ \(score - 2800)" }
        let clamped = max(score, 0)
        let tier = tiers[clamped / 400]
        return "\(tier.prefix(1) + tier.dropFirst().lowercased()) \(divisions[clamped % 400 / 100])"
    }

    func sameStanding(as other: RankSnapshot) -> Bool {
        tier == other.tier && division == other.division && leaguePoints == other.leaguePoints && wins == other.wins && losses == other.losses
    }
}

extension RankSnapshot {
    init?(_ queue: RankedQueue?, at date: Date) {
        guard let queue, queue.isRanked, let tier = queue.tier else { return nil }
        self.init(date: date, tier: tier, division: queue.division, leaguePoints: queue.leaguePoints ?? 0,
                  wins: queue.wins ?? 0, losses: queue.losses ?? 0)
    }
}

/// LP change with its sign, such as "+18 LP".
func signedLP(_ change: Int) -> String { "\(change > 0 ? "+" : "")\(change) LP" }

extension Array where Element == RankSnapshot {
    /// LP gained since `date`, measured from the last reading before it; nil when no ranked game was recorded since.
    func lpChange(since date: Date) -> Int? {
        guard let latest = last, let base = last(where: { $0.date < date }) ?? first(where: { $0.date >= date }), base != latest else { return nil }
        return latest.score - base.score
    }
}

/// LP history of the signed-in player per ranked queue, kept on disk because the client only reports the current rank.
actor RankHistory {
    enum Queue: String, CaseIterable, Sendable { case solo, flex }

    private let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "UP", isDirectory: true)
        .appendingPathComponent("Ranks", isDirectory: true)
    private var loaded: [String: [String: [RankSnapshot]]] = [:]

    /// Adds the queue's current standing when it changed and returns the queue's history, oldest first.
    func record(_ queue: RankedQueue?, as kind: Queue, puuid: String) -> [RankSnapshot] {
        var all = history(puuid)
        var list = all[kind.rawValue] ?? []
        if let snapshot = RankSnapshot(queue, at: Date()), !(list.last?.sameStanding(as: snapshot) ?? false) {
            list = Array((list + [snapshot]).suffix(500))
            all[kind.rawValue] = list
            loaded[puuid] = all
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? JSONEncoder().encode(all).write(to: file(puuid), options: .atomic)
        }
        return list
    }

    private func history(_ puuid: String) -> [String: [RankSnapshot]] {
        if let cached = loaded[puuid] { return cached }
        let stored = (try? Data(contentsOf: file(puuid))).flatMap { try? JSONDecoder().decode([String: [RankSnapshot]].self, from: $0) } ?? [:]
        loaded[puuid] = stored
        return stored
    }

    private func file(_ puuid: String) -> URL { folder.appendingPathComponent("\(puuid).json") }
}

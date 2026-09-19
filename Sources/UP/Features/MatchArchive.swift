import Foundation

/// Keeps every match of the signed-in player that the client has listed, because the client itself only lists the last 20.
actor MatchArchive {
    private let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "UP", isDirectory: true)
        .appendingPathComponent("Matches", isDirectory: true)
    private var loaded: [String: [HistoryGame]] = [:]

    /// Adds newly listed games to the player's archive, which keeps the latest 1000.
    func add(_ games: [HistoryGame], puuid: String) {
        var all = archive(puuid)
        let known = Set(all.map(\.gameId))
        let fresh = games.filter { !known.contains($0.gameId) }
        guard !fresh.isEmpty else { return }
        all = Array((all + fresh).sorted { ($0.gameCreation ?? 0) > ($1.gameCreation ?? 0) }.prefix(1000))
        loaded[puuid] = all
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(all).write(to: file(puuid), options: .atomic)
    }

    /// Archived games that started before `time` (milliseconds), newest first.
    func games(before time: Double, puuid: String, limit: Int) -> [HistoryGame] {
        Array(archive(puuid).filter { ($0.gameCreation ?? 0) < time }.prefix(limit))
    }

    private func archive(_ puuid: String) -> [HistoryGame] {
        if let cached = loaded[puuid] { return cached }
        let games = (try? Data(contentsOf: file(puuid))).flatMap { try? jsonDecoder.decode([HistoryGame].self, from: $0) } ?? []
        loaded[puuid] = games
        return games
    }

    private func file(_ puuid: String) -> URL { folder.appendingPathComponent("\(puuid).json") }
}

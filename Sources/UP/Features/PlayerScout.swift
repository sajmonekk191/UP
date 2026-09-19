import Foundation

/// Porofessor-style summary of a player built from their rank and recent matches.
struct PlayerProfile: Sendable, Identifiable {
    struct ChampionRecord: Sendable, Hashable, Identifiable {
        var championId: Int
        var games: Int
        var wins: Int
        var kills: Int, deaths: Int, assists: Int
        var id: Int { championId }
        var winRate: Double { games > 0 ? Double(wins) / Double(games) : 0 }
        var kda: Double { Double(kills + assists) / Double(max(deaths, 1)) }
    }

    struct Tag: Sendable, Hashable, Identifiable {
        enum Tone: Sendable { case good, bad, info }
        var text: String
        var tone: Tone
        var help: String
        var id: String { text }
    }

    var puuid: String
    var summoner: Summoner?
    var solo: RankedQueue?
    var flex: RankedQueue?
    var recent: [HistoryGame]
    var champions: [ChampionRecord]
    var masteries: [ChampionMastery] = []
    var tags: [Tag] = []
    /// Server of a profile loaded from op.gg; nil when it came from the signed-in client.
    var region: Region?
    /// Ranked champions of the current season, known for op.gg profiles.
    var seasonChampions: [ChampionRecord] = []

    /// Per-minute averages over countable recent games.
    struct Averages: Sendable {
        var csPerMin = 0.0, damagePerMin = 0.0, visionPerMin = 0.0
    }

    var averages: Averages {
        let games = recentGames.compactMap { g in g.me.map { (g.minutes, $0.stats) } }
        guard !games.isEmpty else { return Averages() }
        let n = Double(games.count)
        var a = Averages()
        for (minutes, s) in games {
            a.csPerMin += Double(s.cs) / minutes / n
            a.damagePerMin += Double(s.totalDamageDealtToChampions ?? 0) / minutes / n
            a.visionPerMin += Double(s.visionScore ?? 0) / minutes / n
        }
        return a
    }

    /// Share of recent games per lane, most played first.
    var roleShares: [(lane: Lane, share: Double)] {
        let lanes = recentGames.compactMap { $0.me?.lane }
        guard !lanes.isEmpty else { return [] }
        return Dictionary(grouping: lanes, by: { $0 }).map { ($0.key, Double($0.value.count) / Double(lanes.count)) }
            .sorted { $0.1 > $1.1 }
    }

    var id: String { puuid }
    /// True when none of the recent games are real matches, so stats fall back to Practice Tool and custom games.
    var usesPracticeGames: Bool { !recent.isEmpty && !recent.contains(where: \.isCountable) }
    var recentGames: [HistoryGame] { usesPracticeGames ? recent.filter { !$0.isRemake } : recent.filter(\.isCountable) }
    var recentWins: Int { recentGames.filter { $0.me?.stats.win == true }.count }
    var recentWinRate: Double? { recentGames.isEmpty ? nil : Double(recentWins) / Double(recentGames.count) }

    var averageKDA: (k: Double, d: Double, a: Double) {
        let games = recentGames.compactMap(\.me?.stats)
        guard !games.isEmpty else { return (0, 0, 0) }
        let n = Double(games.count)
        return (Double(games.map { $0.kills ?? 0 }.reduce(0, +)) / n,
                Double(games.map { $0.deaths ?? 0 }.reduce(0, +)) / n,
                Double(games.map { $0.assists ?? 0 }.reduce(0, +)) / n)
    }

    /// Win (true) / loss (false) sequence, newest first.
    var form: [Bool] { recentGames.prefix(10).map { $0.me?.stats.win == true } }

    var streak: Int {
        guard let first = form.first else { return 0 }
        let length = form.prefix { $0 == first }.count
        return first ? length : -length
    }

    func record(for championId: Int) -> ChampionRecord? {
        champions.first { $0.championId == championId }
    }
}

/// Loads and caches player profiles through the League client.
actor PlayerScout {
    private var cache: [String: (date: Date, profile: PlayerProfile)] = [:]
    private var details: [Int: HistoryGame] = [:]

    func profile(puuid: String, client: LCUClient, historyCount: Int = 20) async -> PlayerProfile {
        if let hit = cache[puuid], Date().timeIntervalSince(hit.date) < 300 { return hit.profile }

        async let summoner: Summoner? = try? client.get("/lol-summoner/v2/summoners/puuid/\(puuid)")
        async let ranked: RankedStats? = try? client.get("/lol-ranked/v1/ranked-stats/\(puuid)")
        async let history: MatchHistoryResponse? = try? client.get(
            "/lol-match-history/v1/products/lol/\(puuid)/matches?begIndex=0&endIndex=\(historyCount - 1)")

        async let mastery: [ChampionMastery]? = try? client.get("/lol-champion-mastery/v1/\(puuid)/champion-mastery")

        let games = (await history)?.games?.games ?? []
        let rankedStats = await ranked
        var profile = PlayerProfile(puuid: puuid, summoner: await summoner,
                                    solo: rankedStats?.solo, flex: rankedStats?.flex,
                                    recent: games, champions: Self.championRecords(games.contains(where: \.isCountable) ? games.filter(\.isCountable) : games))
        profile.masteries = (await mastery ?? []).sorted { ($0.championPoints ?? 0) > ($1.championPoints ?? 0) }
        profile.tags = profile.usesPracticeGames ? [] : Self.tags(for: profile)
        cache[puuid] = (Date(), profile)
        return profile
    }

    func invalidate() { cache.removeAll() }

    /// Profile on any server from op.gg, cached for five minutes.
    func remoteProfile(_ query: PlayerQuery) async -> PlayerProfile? {
        let key = "\(query.region.rawValue)|\(query.riotId.lowercased())"
        if let hit = cache[key], Date().timeIntervalSince(hit.date) < 300 { return hit.profile }
        guard let profile = try? await OpggAccounts.profile(query) else { return nil }
        cache[key] = (Date(), profile)
        return profile
    }

    /// Full 10-player details of one match.
    func game(_ gameId: Int, client: LCUClient) async -> HistoryGame? {
        if let cached = details[gameId] { return cached }
        let game: HistoryGame? = try? await client.get("/lol-match-history/v1/games/\(gameId)")
        details[gameId] = game
        return game
    }

    /// Details already fetched for these games, keyed by game id.
    func details(for ids: [Int]) -> [Int: HistoryGame] {
        details.filter { ids.contains($0.key) }
    }

    /// Grades the player in each game against everyone else in that match.
    func performances(of recent: [HistoryGame], puuid: String, client: LCUClient) async -> [Int: GamePerformance] {
        await withTaskGroup(of: (Int, GamePerformance?).self) { group in
            for game in recent where !game.isRemake {
                group.addTask {
                    let detail = await self.game(game.gameId, client: client)
                    return (game.gameId, GamePerformance(game: detail ?? game, puuid: puuid))
                }
            }
            var result: [Int: GamePerformance] = [:]
            for await (id, performance) in group { result[id] = performance }
            return result
        }
    }

    static func championRecords(_ games: [HistoryGame]) -> [PlayerProfile.ChampionRecord] {
        var records: [Int: PlayerProfile.ChampionRecord] = [:]
        for game in games where !game.isRemake {
            guard let me = game.me else { continue }
            var r = records[me.championId] ?? .init(championId: me.championId, games: 0, wins: 0, kills: 0, deaths: 0, assists: 0)
            r.games += 1
            r.wins += me.stats.win == true ? 1 : 0
            r.kills += me.stats.kills ?? 0
            r.deaths += me.stats.deaths ?? 0
            r.assists += me.stats.assists ?? 0
            records[me.championId] = r
        }
        return records.values.sorted { $0.games > $1.games }
    }

    static func tags(for p: PlayerProfile) -> [PlayerProfile.Tag] {
        var tags: [PlayerProfile.Tag] = []
        let games = p.recentGames.count

        if p.streak >= 3 { tags.append(.init(text: tr("🔥 %d win streak", p.streak), tone: .good, help: tr("On a winning streak."))) }
        if p.streak <= -3 { tags.append(.init(text: tr("🧊 %d loss streak", -p.streak), tone: .bad, help: tr("On a losing streak, may be tilted."))) }

        if let level = p.summoner?.summonerLevel, level < 60, games >= 8, let wr = p.recentWinRate, wr >= 0.65 {
            tags.append(.init(text: tr("Smurf?"), tone: .info, help: tr("Low level (%d) but %d%% wins in recent games.", level, Int(wr * 100))))
        }
        if let solo = p.solo, let wr = solo.winRate, solo.games >= 30, wr >= 0.58 {
            tags.append(.init(text: tr("Strong in ranked"), tone: .good, help: tr("%d%% wins in %d ranked games.", Int(wr * 100), solo.games)))
        }
        let kda = p.averageKDA
        if games >= 5, kda.d >= 7.5 { tags.append(.init(text: tr("Dies a lot"), tone: .bad, help: tr("%.1f deaths per game on average.", kda.d))) }
        if games >= 5, kda.k >= 9 { tags.append(.init(text: tr("Carry"), tone: .good, help: tr("%.1f kills per game on average.", kda.k))) }
        if let top = p.champions.first, games >= 8, Double(top.games) / Double(games) >= 0.5 {
            tags.append(.init(text: tr("One-trick"), tone: .info, help: tr("%d of the last %d games on one champion.", top.games, games)))
        }
        if let prev = p.solo?.previousSeasonEndTier, !prev.isEmpty, prev != "NONE", !(p.solo?.isRanked ?? false) {
            tags.append(.init(text: tr("Last season: %@", prev.prefix(1) + prev.dropFirst().lowercased()), tone: .info, help: tr("Final rank last season.")))
        }
        if let top = p.masteries.first, (top.championPoints ?? 0) >= 500_000 {
            tags.append(.init(text: tr("Mastery %dk", (top.championPoints ?? 0) / 1000), tone: .good, help: tr("Over half a million points on one champion.")))
        }
        if let date = p.recent.first?.date, Date().timeIntervalSince(date) > 30 * 86400 {
            tags.append(.init(text: tr("Inactive"), tone: .info, help: tr("Last game more than a month ago.")))
        }
        return tags
    }
}

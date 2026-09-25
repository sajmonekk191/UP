import SwiftUI

/// Profile of a player chosen from the search bar, or recent searches and friends when none is chosen.
struct PlayerView: View, Equatable {
    @Environment(AppModel.self) private var model
    @Binding var query: PlayerQuery?
    var back: BackLink
    @State private var profile: PlayerProfile?
    @State private var performances: [Int: GamePerformance] = [:]
    @State private var grading = false
    @State private var loading = false
    @State private var notFound = false

    /// The query is read through its binding, so only the back link's target matters here.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.back.title == rhs.back.title }

    /// The signed-in client knows its own server best; every other server comes from op.gg.
    private var viaClient: Bool { query?.region == model.clientRegion && model.connection == .connected }

    var body: some View {
        Screen(title: profile?.summoner?.riotId ?? query?.riotId ?? tr("Player"),
               subtitle: query.map { tr("%@ · %@", $0.region.code, $0.region.title) } ?? tr("Search any player on any server"), back: back) {
            if loading, let query { LoadingNote(text: tr("Looking up %@ on %@…", query.riotId, query.region.code)) }
        } content: {
            if notFound {
                Label(tr("No player %@ on %@.", query?.riotId ?? "", query?.region.code ?? ""), systemImage: "questionmark.circle.fill")
                    .foregroundStyle(Theme.warning)
            }
            if let profile {
                ProfileDetail(profile: profile, performances: performances, grading: grading)
            } else if loading {
                ProfileSkeleton(remote: !viaClient)
            } else if query == nil {
                Panel(title: tr("Find a player"), symbol: "magnifyingglass") {
                    Text(tr("Type a name in the search bar at the top (⌘K) and pick the server next to it. Friends and recent searches are suggested as you type."))
                        .foregroundStyle(Theme.textSecondary)
                    let home = model.clientRegion ?? model.searchRegion
                    let people = Array((model.recentPlayers + model.friends.compactMap { $0.riotId.map { PlayerQuery(riotId: $0, region: home) } }).prefix(8))
                    if !people.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(people, id: \.self) { person in
                                Button(person.region == home ? person.riotId : "\(person.riotId) · \(person.region.code)") { query = person }.buttonStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .task(id: "\(query?.stored ?? "")|\(viaClient)") { await load() }
    }

    private func load() async {
        profile = nil
        performances = [:]
        notFound = false
        loading = false
        grading = false
        guard let query, query.riotId.contains("#") else { return }
        let viaClient = self.viaClient
        loading = true
        let found = viaClient ? await model.lookupPlayer(riotId: query.riotId) : await model.remoteProfile(query)
        guard !Task.isCancelled else { return }
        loading = false
        profile = found
        notFound = found == nil
        guard let found else { return }
        model.rememberPlayer(PlayerQuery(riotId: found.summoner?.riotId ?? query.riotId, region: query.region))
        if viaClient {
            grading = true
            let graded = await model.performances(for: found)
            guard !Task.isCancelled else { return }
            performances = graded
            grading = false
        } else {
            performances = GamePerformance.all(in: found)
        }
    }
}

/// Full profile: identity, ranks, averages, champions, mastery and graded matches.
struct ProfileDetail: View {
    @Environment(AppModel.self) private var model
    let profile: PlayerProfile
    let performances: [Int: GamePerformance]
    var grading = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Panel {
                HStack(spacing: 16) {
                    LCUImage(path: profile.summoner?.profileIconId.map { "/lol-game-data/assets/v1/profile-icons/\($0).jpg" }, size: 64, corner: 32)
                        .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 2))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(profile.summoner?.riotId ?? "").font(.title2.weight(.bold)).foregroundStyle(Theme.text)
                        HStack(spacing: 6) {
                            if let region = profile.region { Chip(text: region.code, tone: .accent, symbol: "globe.europe.africa.fill") }
                            Chip(text: tr("Level %d", profile.summoner?.summonerLevel ?? 0), tone: .neutral)
                            FlowTags(tags: profile.tags)
                        }
                    }
                    Spacer()
                    RankBlock(title: tr("Solo / Duo"), queue: profile.solo)
                    RankBlock(title: tr("Flex"), queue: profile.flex).padding(.leading, 20)
                }
            }
            let a = profile.averages, kda = profile.averageKDA
            HStack(spacing: 12) {
                if profile.usesPracticeGames {
                    StatTile(label: tr("Win rate"), value: "—", sub: tr("Practice games have no result"))
                } else {
                    StatTile(label: tr("Win rate"), value: percent(profile.recentWinRate, digits: 0), sub: tr("%d countable games", profile.recentGames.count),
                             valueColor: winRateColor(profile.recentWinRate))
                }
                StatTile(label: "KDA", value: "\(decimal(kda.k)) / \(decimal(kda.d)) / \(decimal(kda.a))",
                         sub: "\(decimal((kda.k + kda.a) / max(kda.d, 1), 2)) KDA")
                StatTile(label: tr("CS / min"), value: decimal(a.csPerMin, 1), sub: tr("farm per minute"))
                StatTile(label: tr("Dmg / min"), value: compact(a.damagePerMin), sub: tr("to champions"))
                StatTile(label: tr("Vision / min"), value: decimal(a.visionPerMin, 2), sub: tr("vision score per minute"))
            }
            HStack(alignment: .top, spacing: Theme.gap) {
                Panel(title: tr("Champions (last 20 games)"), symbol: "person.crop.square") {
                    ForEach(profile.champions.prefix(5)) { record in
                        HStack(spacing: 10) {
                            ChampionIcon(id: record.championId, size: 30)
                            Text(model.gameData.championName(record.championId)).foregroundStyle(Theme.text).frame(width: 120, alignment: .leading)
                            if profile.usesPracticeGames {
                                Spacer()
                                Text(gamesLabel(record.games)).font(.caption).foregroundStyle(Theme.textMuted)
                            } else {
                                WinRateMeter(winRate: record.winRate, games: record.games)
                            }
                        }
                    }
                }
                if profile.masteries.isEmpty, !profile.seasonChampions.isEmpty {
                    Panel(title: tr("Ranked this season"), symbol: "trophy.fill") {
                        ForEach(profile.seasonChampions.prefix(5)) { record in
                            HStack(spacing: 10) {
                                ChampionIcon(id: record.championId, size: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(model.gameData.championName(record.championId)).foregroundStyle(Theme.text).lineLimit(1)
                                    Text("\(decimal(record.kda, 2)) KDA · \(gamesLabel(record.games))").font(.caption2).foregroundStyle(Theme.textMuted)
                                }
                                Spacer()
                                Text(percent(record.winRate, digits: 0)).font(.callout.weight(.semibold).monospacedDigit()).foregroundStyle(winRateColor(record.winRate))
                            }
                        }
                    }
                    .frame(width: 340)
                }
                if !profile.masteries.isEmpty {
                    Panel(title: tr("Top mastery"), symbol: "star.fill") {
                        ForEach(profile.masteries.prefix(5), id: \.championId) { mastery in
                            HStack(spacing: 10) {
                                ChampionIcon(id: mastery.championId, size: 30)
                                Text(model.gameData.championName(mastery.championId)).foregroundStyle(Theme.text)
                                Spacer()
                                Text("M\(mastery.championLevel ?? 0)").font(.caption.weight(.bold)).foregroundStyle(Theme.gold)
                                Text(compact(Double(mastery.championPoints ?? 0))).font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary).frame(width: 60, alignment: .trailing)
                            }
                        }
                    }
                    .frame(width: 340)
                }
            }
            Panel(title: tr("Recent matches"), symbol: "clock.arrow.circlepath") {
                if let average = AverageGrade.mean(profile.recent, performances) { AverageGrade(score: average) }
            } content: {
                MatchList(games: profile.recent, performances: performances, grading: grading, lazy: true)
            }
        }
    }
}

/// Every recent match of the signed-in player with grades, a season-style summary and full match details.
struct HistoryView: View, Equatable {
    @Environment(AppModel.self) private var model
    var back: BackLink

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.back.title == rhs.back.title }

    var body: some View {
        Screen(title: tr("Match history"), subtitle: tr("Click a match to see all players with their grades"), back: back) {
            RefreshButton()
        } content: {
            if let profile = model.myProfile {
                let games = profile.recent + model.olderMatches
                summary(games)
                MatchList(games: games, performances: model.myPerformance, grading: model.isGrading, lazy: true)
                olderMatches
            } else {
                HStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in StatTileSkeleton() }
                }
                MatchListSkeleton(count: 6)
            }
        }
        .environment(\.shimmers, model.connection == .connected)
    }

    /// Loads matches older than the client's last 20 on request.
    @ViewBuilder
    private var olderMatches: some View {
        if model.isLoadingOlder {
            MatchListSkeleton(count: 3)
        } else if model.olderExhausted {
            Label(tr("No older matches found. The client only lists your last 20 games, so UP! now keeps every game it sees for you."), systemImage: "clock.arrow.circlepath")
                .font(.callout).foregroundStyle(Theme.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else {
            Button { Task { await model.loadOlderMatches() } } label: { Label(tr("Show more"), systemImage: "chevron.down") }
                .buttonStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }

    private func summary(_ games: [HistoryGame]) -> some View {
        let graded = games.compactMap { game in model.myPerformance[game.id].map { (game, $0) } }
        let average = AverageGrade.mean(games, model.myPerformance)
        let best = graded.filter { $0.1.score != nil }.max { ($0.1.score ?? 0) < ($1.1.score ?? 0) }
        let badges = graded.flatMap(\.1.badges).filter { $0 != .mvp && $0 != .ace }
        let favourite = Dictionary(grouping: badges, by: { $0 }).max { $0.value.count < $1.value.count }
        return HStack(spacing: 12) {
            StatTile(label: tr("Average grade"), value: average.map { GamePerformance.Grade(score: $0).rawValue } ?? "—",
                     sub: average.map { tr("%@ of 10 over %d games", decimal($0, 1), graded.count) } ?? tr("No graded games yet"),
                     valueColor: average.map { GamePerformance.Grade(score: $0).color } ?? Theme.textSecondary)
            StatTile(label: "MVP", value: "\(graded.filter { $0.1.badges.contains(.mvp) }.count)",
                     sub: tr("%d × ACE", graded.filter { $0.1.badges.contains(.ace) }.count))
            StatTile(label: tr("Best game"), value: best?.1.grade?.rawValue ?? "—",
                     sub: best.map { game, _ in
                         "\(model.gameData.championName(game.me?.championId)) · \(game.me?.stats.kills ?? 0)/\(game.me?.stats.deaths ?? 0)/\(game.me?.stats.assists ?? 0)"
                     } ?? tr("No graded games yet"),
                     valueColor: best?.1.grade?.color ?? Theme.textSecondary)
            StatTile(label: tr("Badges earned"), value: "\(badges.count)",
                     sub: favourite.map { tr("Most often: %@ × %d", $0.key.title, $0.value.count) } ?? tr("No badges yet"))
        }
    }
}

/// Placeholder in the shape of a player profile; op.gg profiles show ranked champions where the client shows mastery.
private struct ProfileSkeleton: View {
    let remote: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Panel {
                HStack(spacing: 16) {
                    Bone(width: 64, height: 64, radius: 32).shimmering()
                    VStack(alignment: .leading, spacing: 5) {
                        Bone(width: 190, height: 18, line: 26, radius: 5)
                        HStack(spacing: 6) {
                            Bone(width: 58, height: 18, radius: 9)
                            Bone(width: 64, height: 18, radius: 9)
                            Bone(width: 84, height: 18, radius: 9)
                        }
                    }
                    .shimmering()
                    Spacer()
                    RankBlockSkeleton(title: tr("Solo / Duo"))
                    RankBlockSkeleton(title: tr("Flex")).padding(.leading, 20)
                }
            }
            HStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in StatTileSkeleton() }
            }
            HStack(alignment: .top, spacing: Theme.gap) {
                Panel(title: tr("Champions (last 20 games)"), symbol: "person.crop.square") { RowsSkeleton(trailing: 150) }
                Panel(title: remote ? tr("Ranked this season") : tr("Top mastery"), symbol: remote ? "trophy.fill" : "star.fill") { RowsSkeleton(trailing: 40) }
                    .frame(width: 340)
            }
            Panel(title: tr("Recent matches"), symbol: "clock.arrow.circlepath") { MatchListSkeleton(count: 5) }
        }
    }
}

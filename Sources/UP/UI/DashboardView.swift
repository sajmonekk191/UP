import SwiftUI

struct DashboardView: View, Equatable {
    @Environment(AppModel.self) private var model
    var showHistory: () -> Void
    var openBuild: (Int) -> Void

    /// The overview only changes with the model it observes; the history and build actions are always the same.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { true }

    var body: some View {
        Screen(title: tr("Overview"), subtitle: model.connection != .connected ? tr("Waiting for the League client…") : model.phase == "None" ? tr("Connected to the client") : tr("Connected to the client · %@", model.phaseTitle)) {
            RefreshButton()
        } content: {
            ProfileHero()
            if let profile = model.myProfile {
                if profile.usesPracticeGames {
                    Label(tr("Your last %d games are all Practice Tool or custom games, so the stats below come from them. The client only shares your 20 most recent games; play a real match to see normal and ranked stats.", profile.recent.count), systemImage: "info.circle.fill")
                        .font(.callout).foregroundStyle(Theme.textSecondary)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .panelBackground(Theme.accentDeep.opacity(0.25), radius: 12)
                }
                if profile.streak <= -3, let last = profile.recentGames.first?.date, Calendar.current.isDateInToday(last) {
                    Label(tr("%d losses in a row. A short break before the next game usually helps.", -profile.streak), systemImage: "cup.and.saucer.fill")
                        .font(.callout).foregroundStyle(Theme.warning)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .panelBackground(Theme.warning.opacity(0.12), radius: 12)
                }
                statTiles(profile)
                HStack(alignment: .top, spacing: Theme.gap) {
                    VStack(spacing: Theme.gap) {
                        if model.rankHistory.values.contains(where: { !$0.isEmpty }) { RankedProgressPanel() }
                        RecentMatchesPanel(games: Array(profile.recent.filter { !$0.isRemake }.prefix(8)), showAll: showHistory)
                            .environment(\.panelFillsHeight, true)
                    }
                    VStack(spacing: Theme.gap) {
                        AutomationPanel()
                        masteryPanel
                        championsPanel(profile).environment(\.panelFillsHeight, true)
                    }
                    .frame(width: 340)
                }
                .fixedSize(horizontal: false, vertical: true)
                ChampionPoolPanel(profile: profile, open: openBuild)
            } else {
                skeleton
            }
        }
    }

    /// Layout of the loaded overview with placeholders, which only shimmer while the client is connected and loading.
    private var skeleton: some View {
        VStack(spacing: Theme.gap) {
            HStack(spacing: 12) {
                ForEach(0..<6, id: \.self) { _ in StatTileSkeleton() }
            }
            HStack(alignment: .top, spacing: Theme.gap) {
                Panel(title: tr("Recent matches"), symbol: "clock.arrow.circlepath") {
                    MatchListSkeleton(count: 8)
                }
                .environment(\.panelFillsHeight, true)
                VStack(spacing: Theme.gap) {
                    AutomationPanel()
                    Panel(title: tr("Mastery"), symbol: "star.fill") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 12) {
                            ForEach(0..<8, id: \.self) { _ in
                                VStack(spacing: 4) {
                                    Bone(width: 44, height: 44, radius: 10.5)
                                    Bone(width: 22, height: 8, line: 13)
                                    Bone(width: 30, height: 7, line: 12)
                                }
                            }
                        }
                        .shimmering()
                    }
                    Panel(title: tr("Most played champions"), symbol: "person.crop.square.filled.and.at.rectangle") {
                        RowsSkeleton(trailing: 72)
                    }
                    .environment(\.panelFillsHeight, true)
                }
                .frame(width: 340)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .environment(\.shimmers, model.connection == .connected)
    }

    private func statTiles(_ profile: PlayerProfile) -> some View {
        let a = profile.averages
        let kda = profile.averageKDA
        let hasGames = !profile.recentGames.isEmpty
        let today = profile.recentGames.filter { Calendar.current.isDateInToday($0.date ?? .distantPast) }
        let todayWins = today.filter { $0.me?.stats.win == true }.count
        let midnight = Calendar.current.startOfDay(for: Date())
        let lpToday = (model.rankHistory[.solo] ?? []).lpChange(since: midnight) ?? (model.rankHistory[.flex] ?? []).lpChange(since: midnight)
        func value(_ text: String) -> String { hasGames ? text : "—" }
        return HStack(spacing: 12) {
            if profile.usesPracticeGames {
                StatTile(label: tr("Win rate"), value: "—", sub: tr("Practice games have no result"))
                StatTile(label: tr("Today"), value: today.isEmpty ? "—" : "\(today.count)", sub: today.isEmpty ? tr("No games yet") : tr("games played today"))
            } else {
                StatTile(label: tr("Win rate"), value: value(percent(profile.recentWinRate, digits: 0)),
                         sub: tr("%dW / %dL", profile.recentWins, profile.recentGames.count - profile.recentWins), valueColor: winRateColor(profile.recentWinRate),
                         trend: rollingWinRate(profile))
                StatTile(label: tr("Today"), value: today.isEmpty ? "—" : tr("%dW / %dL", todayWins, today.count - todayWins),
                         sub: today.isEmpty ? tr("No games yet") : [tr("%d games today", today.count), lpToday.map(signedLP)].compactMap { $0 }.joined(separator: " · "))
            }
            StatTile(label: "KDA", value: value(decimal((kda.k + kda.a) / max(kda.d, 1), 2)),
                     sub: hasGames ? "\(decimal(kda.k)) / \(decimal(kda.d)) / \(decimal(kda.a))" : tr("No games yet"))
            StatTile(label: tr("CS / min"), value: value(decimal(a.csPerMin, 1)), sub: tr("farm per minute"))
            StatTile(label: tr("Dmg / min"), value: value(compact(a.damagePerMin)), sub: tr("to champions"))
            StatTile(label: tr("Vision / min"), value: value(decimal(a.visionPerMin, 2)), sub: tr("vision score per minute"))
        }
    }

    /// Cumulative win rate from oldest to newest game, for the tile sparkline.
    private func rollingWinRate(_ profile: PlayerProfile) -> [Double] {
        var wins = 0.0
        return profile.recentGames.reversed().enumerated().map { index, game in
            wins += game.me?.stats.win == true ? 1 : 0
            return wins / Double(index + 1)
        }
    }

    private func championsPanel(_ profile: PlayerProfile) -> some View {
        let mostGames = Double(max(profile.champions.first?.games ?? 1, 1))
        return Panel(title: tr("Most played champions"), symbol: "person.crop.square.filled.and.at.rectangle") {
            if profile.champions.isEmpty {
                Text(tr("No countable games.")).font(.callout).foregroundStyle(Theme.textSecondary)
            }
            VStack(spacing: 10) {
                ForEach(profile.champions.prefix(5)) { record in
                    HStack(spacing: 10) {
                        ChampionIcon(id: record.championId, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.gameData.championName(record.championId)).font(.callout.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                            Text(profile.usesPracticeGames ? "\(decimal(record.kda, 2)) KDA" : "\(decimal(record.kda, 2)) KDA · \(gamesLabel(record.games))")
                                .font(.caption2).foregroundStyle(Theme.textMuted).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 4) {
                            if profile.usesPracticeGames {
                                Text(gamesLabel(record.games)).font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                                Meter(value: Double(record.games) / mostGames, height: 4).frame(width: 72)
                            } else {
                                let ahead = record.winRate >= 0.495
                                Text(percent(record.winRate, digits: 0)).font(.caption.weight(.semibold)).foregroundStyle(winRateColor(record.winRate))
                                Meter(value: record.winRate, tint: ahead ? Theme.win : Theme.loss, track: ahead ? Theme.accentTrack : Theme.lossTrack, height: 4, marker: 0.5)
                                    .frame(width: 72)
                            }
                        }
                    }
                }
            }
        }
    }

    private var masteryPanel: some View {
        Panel(title: tr("Mastery"), symbol: "star.fill") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 12) {
                ForEach(model.myMasteries.prefix(8), id: \.championId) { mastery in
                    VStack(spacing: 4) {
                        ChampionIcon(id: mastery.championId, size: 44, ring: (mastery.championLevel ?? 0) >= 10 ? Theme.gold : nil)
                        Text("M\(mastery.championLevel ?? 0)").font(.caption.weight(.bold)).foregroundStyle(Theme.gold)
                        Text(compact(Double(mastery.championPoints ?? 0))).font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }
}

/// Splash banner with the player's icon, name, tags and ranks; its own view, so loading champion details redraws only the banner.
private struct ProfileHero: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let splashChampion = model.myProfile?.champions.first?.championId ?? model.myMasteries.first?.championId
        let splash = splashChampion.flatMap { model.gameData.details[$0]?.splashPath }
        return HeroBanner(splashPath: splash, height: 190) {
            HStack(alignment: .center, spacing: 18) {
                LCUImage(path: model.me?.profileIconId.map { "/lol-game-data/assets/v1/profile-icons/\($0).jpg" }, size: 84, corner: 42)
                    .overlay(Circle().strokeBorder(LinearGradient(colors: [Theme.accentBright, Theme.accentDeep], startPoint: .top, endPoint: .bottom), lineWidth: 3))
                    .overlay(alignment: .bottom) {
                        if let level = model.me?.summonerLevel {
                            Text("\(level)").font(.caption.weight(.bold)).foregroundStyle(Theme.text)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Theme.accentDeep, in: Capsule()).overlay(Capsule().strokeBorder(Theme.accent))
                                .offset(y: 8)
                        }
                    }
                VStack(alignment: .leading, spacing: 6) {
                    if let me = model.me {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(me.gameName ?? "—").font(.system(size: 32, weight: .bold)).foregroundStyle(Theme.text)
                            if let tag = me.tagLine { Text("#\(tag)").font(.title3).foregroundStyle(Theme.textSecondary) }
                        }
                    } else {
                        Bone(width: 220, height: 24, line: 38, radius: 6)
                    }
                    if let profile = model.myProfile {
                        FlowTags(tags: profile.tags)
                    } else {
                        HStack(spacing: 4) {
                            Bone(width: 86, height: 18, radius: 9)
                            Bone(width: 64, height: 18, radius: 9)
                        }
                        .shimmering()
                    }
                }
                Spacer()
                HStack(spacing: 28) {
                    if let profile = model.myProfile {
                        RankBlock(title: tr("Solo / Duo"), queue: profile.solo)
                        RankBlock(title: tr("Flex"), queue: profile.flex)
                    } else {
                        RankBlockSkeleton(title: tr("Solo / Duo"))
                        RankBlockSkeleton(title: tr("Flex"))
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
            }
            .environment(\.shimmers, model.connection == .connected)
        }
        .task(id: splashChampion) {
            if let id = splashChampion { _ = await model.gameData.detail(id, client: model.client) }
        }
    }
}

/// Latest matches of the overview with their grades; the full list opens as match history.
private struct RecentMatchesPanel: View {
    @Environment(AppModel.self) private var model
    let games: [HistoryGame]
    var showAll: () -> Void

    var body: some View {
        Panel(title: tr("Recent matches"), symbol: "clock.arrow.circlepath") {
            HStack(spacing: 12) {
                if let average = AverageGrade.mean(games, model.myPerformance) { AverageGrade(score: average) }
                Button(action: showAll) {
                    HStack(spacing: 4) {
                        Text(tr("All matches"))
                        Image(systemName: "arrow.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accentBright)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).handCursor()
            }
        } content: {
            if games.isEmpty {
                Text(tr("No matches yet.")).font(.callout).foregroundStyle(Theme.textSecondary)
            }
            MatchList(games: games, performances: model.myPerformance, grading: model.isGrading)
        }
    }
}

/// LP over time for Solo/Duo or Flex, as UP! recorded it after each ranked game.
private struct RankedProgressPanel: View {
    @Environment(AppModel.self) private var model
    @State private var picked: RankHistory.Queue?

    var body: some View {
        let solo = model.rankHistory[.solo] ?? [], flex = model.rankHistory[.flex] ?? []
        let queue = picked ?? (solo.isEmpty ? .flex : .solo)
        let history = queue == .solo ? solo : flex
        Panel(title: tr("Ranked progress"), symbol: "chart.line.uptrend.xyaxis") {
            if !solo.isEmpty, !flex.isEmpty {
                Segmented(options: [(RankHistory.Queue.solo, tr("Solo / Duo")), (.flex, tr("Flex"))], selection: Binding(get: { queue }, set: { picked = $0 }))
            }
        } content: {
            HStack(spacing: 28) {
                change(tr("Today"), history.lpChange(since: Calendar.current.startOfDay(for: Date())))
                change(tr("Last 7 days"), history.lpChange(since: Date().addingTimeInterval(-7 * 86_400)))
                if let latest = history.last { KeyValue(key: tr("Now"), value: latest.label) }
                Spacer()
            }
            if history.count >= 2 {
                LPChart(snapshots: history)
            } else {
                Text(tr("UP! saves your LP after every ranked game, so this chart fills in as you play."))
                    .font(.callout).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func change(_ title: String, _ lp: Int?) -> some View {
        KeyValue(key: title, value: lp.map(signedLP) ?? "—", color: (lp ?? 0) > 0 ? Theme.win : (lp ?? 0) < 0 ? Theme.loss : Theme.text)
    }
}

/// Your champions in one role rated against this patch, strong picks worth learning and the ones that fell off.
private struct ChampionPoolPanel: View {
    @Environment(AppModel.self) private var model
    let profile: PlayerProfile
    var open: (Int) -> Void
    @State private var lane: Lane?
    @State private var tierList: [TierListEntry] = []

    var body: some View {
        let shown = lane ?? profile.roleShares.first?.lane ?? .middle
        Panel(title: tr("Champion pool"), symbol: "square.stack.3d.up.fill") {
            Segmented(options: Lane.allCases.map { ($0, $0.title) }, selection: Binding(get: { shown }, set: { lane = $0 }))
        } content: {
            if tierList.isEmpty {
                RowsSkeleton(rows: 3, icon: 34, trailing: 40)
            } else {
                let pool = ChampionPool(lane: shown, profile: profile, masteries: model.myMasteries, tierList: tierList, champions: model.gameData.champions)
                HStack(alignment: .top, spacing: 28) {
                    column(tr("Your picks"), pool.played, empty: tr("Play a few games in this role to build your pool."))
                    column(tr("Worth learning"), pool.toLearn, empty: tr("No data."))
                    column(tr("Weak this patch"), pool.weak, empty: tr("None of your picks are weak this patch."))
                }
            }
        }
        .task { tierList = (try? await BuildService.tierList()) ?? [] }
    }

    private func column(_ title: String, _ picks: [ChampionPool.Pick], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).eyebrow()
            if picks.isEmpty { Text(empty).font(.callout).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true) }
            ForEach(picks) { pick in
                Button { open(pick.championId) } label: { row(pick) }.buttonStyle(.plain).handCursor()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func row(_ pick: ChampionPool.Pick) -> some View {
        HStack(spacing: 10) {
            ChampionIcon(id: pick.championId, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.gameData.championName(pick.championId)).font(.callout.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    if let entry = pick.entry {
                        Text(tierName(entry.tier)).font(.caption.weight(.heavy))
                            .foregroundStyle(entry.tier <= 1 ? Theme.gold : entry.tier == 2 ? Theme.accentBright : entry.tier >= 4 ? Theme.loss : Theme.textSecondary)
                        Text(percent(entry.winRate)).font(.caption.monospacedDigit()).foregroundStyle(winRateColor(entry.winRate))
                    }
                }
                Text(detail(pick)).font(.caption).foregroundStyle(Theme.textMuted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func detail(_ pick: ChampionPool.Pick) -> String {
        if pick.games > 0 { return tr("You: %@", tr("%d games · %@", pick.games, percent(pick.winRate, digits: 0))) }
        if pick.sharesClass { return tr("Similar to your picks") }
        if pick.mastery > 0 { return tr("Mastery %@", compact(Double(pick.mastery))) }
        return pick.entry.map { tr("#%d in role", $0.rank) } ?? ""
    }
}

struct AutomationPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Panel(title: tr("Automation"), symbol: "bolt.fill") {
            VStack(spacing: 10) {
                toggle(tr("Auto-accept"), "checkmark.circle", $settings.autoAccept)
                toggle(tr("Champ select window"), "macwindow", $settings.autoOpenChampSelect)
                toggle(tr("Import runes"), "circle.hexagongrid", $settings.autoRunes)
                toggle(tr("Summoner spells"), "sparkles", $settings.autoSpells)
                toggle(tr("Item sets"), "bag", $settings.autoItemSets)
                toggle(tr("Scout teammates"), "person.2", $settings.scoutTeam)
                toggle(tr("In-game HUD"), "rectangle.on.rectangle", $settings.showOverlay)
                toggle(tr("Sounds"), "speaker.wave.2", $settings.soundAlerts)
            }
        }
    }

    private func toggle(_ title: String, _ symbol: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.callout).foregroundStyle(Theme.accentBright).frame(width: 20)
            Text(title).font(.callout).foregroundStyle(Theme.text)
            Spacer()
            Toggle(title, isOn: binding).labelsHidden().toggleStyle(PillToggleStyle())
        }
    }
}

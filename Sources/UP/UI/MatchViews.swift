import SwiftUI

/// Graded match cards that expand to show every player of the game.
struct MatchList: View {
    @Environment(AppModel.self) private var model
    let games: [HistoryGame]
    let performances: [Int: GamePerformance]
    var grading = false
    /// Builds cards only as they scroll into view, for long lists placed directly in a scroll view.
    var lazy = false
    @State private var expanded: Int?

    var body: some View {
        if lazy {
            LazyVStack(spacing: 8) { cards }
        } else {
            VStack(spacing: 8) { cards }
        }
    }

    private var cards: some View {
        ForEach(games.compactMap { game in game.me.map { (game: game, me: $0) } }, id: \.game.id) { game, me in
            let open = expanded == game.id
            VStack(spacing: 0) {
                Button { withAnimation(.snappy(duration: 0.3)) { expanded = open ? nil : game.id } } label: {
                    MatchCard(game: game, me: me, performance: performances[game.id], grading: grading, expanded: open)
                }
                .buttonStyle(.plain).handCursor()
                .help(open ? tr("Hide the players") : tr("Show all players of this match"))
                if open {
                    MatchDetail(game: game, focusPuuid: game.identity(for: me.participantId)?.puuid, cached: model.cachedMatchDetail(game.gameId))
                        .transition(.modifier(active: Fold(progress: 0), identity: Fold(progress: 1)))
                }
            }
            .background(open ? Theme.surface : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// Unfolds from the top edge and folds back up in place, so an opening or closing detail never slides over the cards around it.
private struct Fold: ViewModifier, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .opacity(min(progress * 1.6, 1))
            .mask { Rectangle().scaleEffect(x: 1, y: progress, anchor: .top) }
    }
}

/// Average grade of the graded games in a list, with how it is calculated on hover.
struct AverageGrade: View {
    let score: Double

    var body: some View {
        let grade = GamePerformance.Grade(score: score)
        HStack(spacing: 6) {
            Text(tr("Average")).font(.caption2.weight(.semibold)).foregroundStyle(Theme.textMuted)
            Text(grade.rawValue).font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(grade.color)
            Text(decimal(score, 1)).font(.caption2.monospacedDigit()).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(grade.color.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(grade.color.opacity(0.35)))
        .help(tr("Grades compare your KDA, kill participation, damage, deaths, farm, vision and objectives with everyone else in the match."))
    }

    /// Mean score of the games that have a grade, nil when none do.
    static func mean(_ games: [HistoryGame], _ performances: [Int: GamePerformance]) -> Double? {
        let scores = games.compactMap { performances[$0.id]?.score }
        return scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
    }
}

/// One match: result, champion, KDA, farm, items, badges and the performance grade.
struct MatchCard: View {
    let game: HistoryGame
    let me: HistoryParticipant
    let performance: GamePerformance?
    var grading = false
    var expanded = false
    @State private var hovering = false

    private var tint: Color { !game.isCountable ? Theme.textMuted : me.stats.win == true ? Theme.win : Theme.loss }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 10) {
            result.frame(width: 104, alignment: .leading)
            champion
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 16) {
                    kda.frame(width: 108, alignment: .leading)
                    farm.frame(width: 118, alignment: .leading)
                    items
                }
                badges.frame(maxWidth: .infinity, minHeight: 20, maxHeight: 20, alignment: .leading)
            }
            Spacer(minLength: 8)
            GradeMedal(performance: performance, grading: grading)
        }
        .padding(.leading, 18).padding(.trailing, 12).padding(.vertical, 12)
        .background {
            ZStack(alignment: .leading) {
                (hovering || expanded ? Theme.hover : Theme.raised).opacity(0.45)
                LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0.02)], startPoint: .leading, endPoint: .trailing)
                tint.frame(width: 4)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(expanded ? Theme.hairlineStrong : Theme.hairline))
        .overlay(alignment: .trailing) {
            if hovering || expanded {
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.textMuted)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .padding(.trailing, 3)
            }
        }
        .contentShape(shape)
        .onHover { hovering = $0 }
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(resultTitle).font(.callout.weight(.bold)).foregroundStyle(game.isCountable ? tint : Theme.textSecondary)
            Text(game.queueTitle).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1).minimumScaleFactor(0.75)
            (Text(Image(systemName: "clock")).font(.system(size: 8.5)) + Text(" " + formatTime(Double(game.gameDuration ?? 0))))
                .font(.caption2.monospacedDigit()).foregroundStyle(Theme.textMuted)
            if let date = game.date {
                Text(date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated).locale(Localizer.shared.language.locale)))
                    .font(.caption2).foregroundStyle(Theme.textMuted).lineLimit(1).minimumScaleFactor(0.85)
            }
        }
    }

    private var resultTitle: String {
        if game.isRemake { return tr("Remake") }
        if game.gameMode == "PRACTICETOOL" { return tr("Practice") }
        if !game.isCountable { return tr("Custom") }
        return me.stats.win == true ? tr("Victory") : tr("Defeat")
    }

    private var champion: some View {
        HStack(spacing: 4) {
            ChampionIcon(id: me.championId, size: 50)
                .overlay(alignment: .bottomTrailing) {
                    if let level = me.stats.champLevel {
                        Text("\(level)").font(.system(size: 9.5, weight: .bold).monospacedDigit()).foregroundStyle(Theme.text)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Theme.background, in: Circle())
                            .overlay(Circle().strokeBorder(Theme.hairlineStrong))
                            .offset(x: 5, y: 5)
                    }
                }
            VStack(spacing: 3) {
                SpellIcon(id: me.spell1Id ?? 0, size: 22)
                SpellIcon(id: me.spell2Id ?? 0, size: 22)
            }
            .padding(.leading, 4)
            VStack(spacing: 3) {
                PerkIcon(id: me.stats.perk0 ?? 0, size: 24)
                PerkIcon(id: me.stats.perkSubStyle ?? 0, size: 16)
            }
        }
    }

    private var kda: some View {
        let s = me.stats
        return VStack(alignment: .leading, spacing: 3) {
            (Text("\(s.kills ?? 0)") + Text(" / ").foregroundColor(Theme.textMuted) + Text("\(s.deaths ?? 0)").foregroundColor(Theme.loss)
                + Text(" / ").foregroundColor(Theme.textMuted) + Text("\(s.assists ?? 0)"))
                .font(.system(size: 16, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.text)
            Text("\(decimal(s.kda, 2)) KDA").font(.caption.weight(.semibold))
                .foregroundStyle(s.kda >= 5 ? Theme.gold : s.kda >= 3 ? Theme.accentBright : Theme.textSecondary)
            if let kp = performance?.killParticipation {
                Text("KP \(percent(kp, digits: 0))").font(.caption2).foregroundStyle(Theme.textMuted)
            }
        }
    }

    private var farm: some View {
        let s = me.stats
        return VStack(alignment: .leading, spacing: 3) {
            Text("\(s.cs) CS · \(decimal(Double(s.cs) / game.minutes, 1))/min").font(.caption.weight(.medium)).foregroundStyle(Theme.text)
            Text(tr("%@ dmg · %d vision", compact(Double(s.totalDamageDealtToChampions ?? 0)), s.visionScore ?? 0))
                .font(.caption).foregroundStyle(Theme.textSecondary)
            Text(tr("%@ gold", compact(Double(s.goldEarned ?? 0)))).font(.caption2).foregroundStyle(Theme.textMuted)
        }
        .lineLimit(1)
    }

    private var items: some View {
        let ids = me.stats.items
        return HStack(spacing: 3) {
            ForEach(0..<6, id: \.self) { ItemIcon(id: ids[$0], size: 20) }
            ItemIcon(id: ids[6], size: 20).padding(.leading, 3)
        }
    }

    private var badges: some View {
        FittingRow(spacing: 5) {
            ForEach((performance?.badges ?? []).filter { $0 != .mvp && $0 != .ace }.prefix(3), id: \.self) { badge in
                Chip(text: badge.title, tone: badge.tone, symbol: badge.symbol).help(badge.help)
            }
        }
    }
}

/// Row that measures each child once and leaves out the ones that no longer fit.
private struct FittingRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize]) -> CGSize {
        let total = cache.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(cache.count - 1, 0))
        return CGSize(width: min(total, proposal.width ?? total), height: cache.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize]) {
        var x = bounds.minX
        for (subview, size) in zip(subviews, cache) {
            let fits = x + size.width <= bounds.maxX + 0.5
            subview.place(at: CGPoint(x: fits ? x : bounds.minX - 10_000, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(size))
            x = fits ? x + size.width + spacing : .infinity
        }
    }

    func makeCache(subviews: Subviews) -> [CGSize] {
        subviews.map { $0.sizeThatFits(.unspecified) }
    }
}

/// Score ring with the grade letter and the player's place in the match.
private struct GradeMedal: View {
    let performance: GamePerformance?
    let grading: Bool

    var body: some View {
        let grade = performance?.grade
        let color = grade?.color ?? Theme.textMuted
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(color.opacity(0.1))
                Circle().stroke(Theme.hairlineStrong.opacity(0.6), lineWidth: 3.5)
                if let grade, let score = performance?.score {
                    Circle().trim(from: 0, to: max(score / 10, 0.02))
                        .stroke(color, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: -2) {
                        Text(grade.rawValue).font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(color)
                        Text(decimal(score, 1)).font(.system(size: 9, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    }
                } else if grading {
                    Spinner(size: 55.5, lineWidth: 3.5)
                } else {
                    Text("—").font(.headline).foregroundStyle(Theme.textMuted)
                }
            }
            .frame(width: 52, height: 52)
            .shadow(color: grade == .sPlus ? color.opacity(0.6) : .clear, radius: 10)
            place.frame(height: 16)
        }
        .frame(width: 66)
        .help(help)
    }

    @ViewBuilder
    private var place: some View {
        let badges = performance?.badges ?? []
        if badges.contains(.mvp) {
            tag("MVP", fill: LinearGradient(colors: [Color(hex: 0xFFD978), Theme.gold], startPoint: .top, endPoint: .bottom), ink: Color(hex: 0x2A1C00))
        } else if badges.contains(.ace) {
            tag("ACE", fill: LinearGradient(colors: [Theme.accentBright, Theme.accent], startPoint: .top, endPoint: .bottom), ink: .white)
        } else if let rank = performance?.rank, let players = performance?.players {
            Text("#\(rank) / \(players)").font(.caption2.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.textMuted)
        }
    }

    private func tag(_ title: String, fill: LinearGradient, ink: Color) -> some View {
        Text(title).font(.system(size: 9.5, weight: .heavy)).tracking(0.8).foregroundStyle(ink)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(fill, in: Capsule())
    }

    private var help: String {
        guard let score = performance?.score, let rank = performance?.rank, let players = performance?.players else {
            return grading ? "" : tr("Not enough players in this game to grade it.")
        }
        return tr("Score %@ of 10, #%d of %d players in this match.", decimal(score, 1), rank, players)
    }
}

/// Small grade letter for a player row in the match details.
private struct GradePill: View {
    let score: Double?

    var body: some View {
        if let score {
            let grade = GamePerformance.Grade(score: score)
            Text(grade.rawValue).font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(grade.color)
                .frame(width: 30, height: 18)
                .background(grade.color.opacity(0.14), in: Capsule())
                .help(tr("Score %@ of 10", decimal(score, 1)))
        } else {
            Text("—").font(.caption2).foregroundStyle(Theme.textMuted).frame(width: 30)
        }
    }
}

/// All players of one match with their grades, damage and gold; the client's list games are completed on demand.
struct MatchDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openPlayer) private var openPlayer
    let source: HistoryGame
    let focusPuuid: String?
    @State private var game: HistoryGame?
    @State private var scores: [Int: Double] = [:]
    @State private var failed = false

    init(game: HistoryGame, focusPuuid: String?, cached: HistoryGame? = nil) {
        source = game
        self.focusPuuid = focusPuuid
        let full = (game.participants?.count ?? 0) > 1 ? game : cached
        _game = State(initialValue: full)
        _scores = State(initialValue: full.map(GamePerformance.scores(in:)) ?? [:])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let game {
                let teams = Dictionary(grouping: game.participants ?? [], by: { $0.teamId ?? 0 }).sorted { $0.key < $1.key }
                ForEach(teams, id: \.key) { teamId, players in
                    teamBlock(game, teamId, players.sorted { (scores[$0.participantId ?? 0] ?? 0) > (scores[$1.participantId ?? 0] ?? 0) })
                }
                if (game.participants?.count ?? 0) > 1 {
                    HStack(alignment: .top, spacing: Theme.gap) {
                        Panel(title: tr("Damage to champions"), symbol: "flame.fill") { PlayerBarChart(rows: rows(game) { Double($0.totalDamageDealtToChampions ?? 0) }) }
                        Panel(title: tr("Gold earned"), symbol: "dollarsign.circle.fill") { PlayerBarChart(rows: rows(game) { Double($0.goldEarned ?? 0) }) }
                    }
                }
            } else if failed {
                Label(tr("The client did not send the details of this match."), systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(Theme.warning).padding(4)
            } else {
                MatchDetailSkeleton()
            }
        }
        .padding(12)
        .task {
            guard game == nil else { return }
            let full = (source.participants?.count ?? 0) > 1 ? source : await model.matchDetail(source.gameId)
            guard let full else { failed = true; return }
            scores = GamePerformance.scores(in: full)
            withAnimation(.easeOut(duration: 0.2)) { game = full }
        }
    }

    private func focusTeam(_ game: HistoryGame) -> Int? {
        let pid = game.participantIdentities?.first { $0.player.puuid == focusPuuid }?.participantId
        return game.participants?.first { $0.participantId == pid }?.teamId
    }

    private func rows(_ game: HistoryGame, _ value: (HistoryStats) -> Double) -> [PlayerBarChart.Row] {
        let myTeam = focusTeam(game)
        return (game.participants ?? []).map { p in
            .init(id: "\(p.participantId ?? 0)", label: model.gameData.championName(p.championId), value: value(p.stats), ally: p.teamId == myTeam)
        }
        .sorted { $0.value > $1.value }
    }

    private func teamBlock(_ game: HistoryGame, _ teamId: Int, _ players: [HistoryParticipant]) -> some View {
        let team = game.teams?.first { $0.teamId == teamId }
        let won = team?.win == "Win"
        let isMine = teamId == focusTeam(game)
        let teamKills = max(players.compactMap(\.stats.kills).reduce(0, +), 1)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                if game.isCountable {
                    Text(won ? tr("Victory") : tr("Defeat")).font(.callout.weight(.bold)).foregroundStyle(won ? Theme.win : Theme.loss)
                }
                Text(isMine ? tr("Your team") : tr("Opponents")).eyebrow()
                Spacer()
                if let team {
                    objective("building.2.fill", team.towerKills, tr("Turrets"))
                    objective("flame.fill", team.dragonKills, tr("Dragons"))
                    objective("ant.fill", team.hordeKills, tr("Voidgrubs"))
                    objective("eye.fill", team.riftHeraldKills, tr("Rift Herald"))
                    objective("crown.fill", team.baronKills, "Baron")
                    let bans = (team.bans ?? []).filter { $0.championId > 0 }
                    if !bans.isEmpty {
                        HStack(spacing: 2) {
                            ForEach(Array(bans.enumerated()), id: \.offset) { ChampionIcon(id: $0.element.championId, size: 20).opacity(0.6) }
                        }
                        .help(tr("Bans"))
                    }
                }
            }
            .padding(.bottom, 2)
            ForEach(players, id: \.participantId) { p in
                let identity = game.identity(for: p.participantId)
                let focused = identity?.puuid == focusPuuid
                let riotId = identity?.riotId ?? ""
                if riotId.isEmpty {
                    playerRow(p, identity: identity, focused: focused, teamKills: teamKills)
                } else {
                    Button { openPlayer?(PlayerQuery(riotId: riotId, region: model.searchRegion)) } label: {
                        playerRow(p, identity: identity, focused: focused, teamKills: teamKills)
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain).handCursor()
                    .help(tr("Open the profile of %@", riotId))
                }
            }
        }
        .padding(10)
        .background((isMine ? Theme.ally : Theme.enemy).opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func playerRow(_ p: HistoryParticipant, identity: ParticipantIdentity.Player?, focused: Bool, teamKills: Int) -> some View {
        HStack(spacing: 8) {
            ChampionIcon(id: p.championId, size: 30, ring: focused ? Theme.gold : nil)
            HStack(spacing: 2) { SpellIcon(id: p.spell1Id ?? 0, size: 15); SpellIcon(id: p.spell2Id ?? 0, size: 15) }
            PerkIcon(id: p.stats.perk0 ?? 0, size: 18)
            Text(identity.map { $0.riotId.isEmpty ? tr("Bot") : $0.riotId } ?? "?")
                .font(.callout.weight(focused ? .semibold : .regular)).foregroundStyle(focused ? Theme.gold : Theme.text)
                .lineLimit(1).frame(minWidth: 80, maxWidth: 170, alignment: .leading)
            GradePill(score: scores[p.participantId ?? 0])
            Text("\(p.stats.kills ?? 0)/\(p.stats.deaths ?? 0)/\(p.stats.assists ?? 0)").font(.callout.monospacedDigit()).foregroundStyle(Theme.text)
                .frame(width: 66, alignment: .leading)
            Text("KP \(percent(Double((p.stats.kills ?? 0) + (p.stats.assists ?? 0)) / Double(teamKills), digits: 0))")
                .frame(width: 50, alignment: .leading)
            Text("\(p.stats.cs) CS").frame(width: 50, alignment: .leading)
            Text(tr("%@ dmg", compact(Double(p.stats.totalDamageDealtToChampions ?? 0)))).frame(width: 64, alignment: .leading)
            Text(tr("%d vis", p.stats.visionScore ?? 0)).foregroundStyle(Theme.textMuted).frame(width: 42, alignment: .leading)
            HStack(spacing: 2) { ForEach(Array(p.stats.items.enumerated()), id: \.offset) { ItemIcon(id: $0.element, size: 20) } }
            Spacer(minLength: 0)
        }
        .font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
        .padding(.vertical, 3).padding(.horizontal, 6)
        .background(focused ? Theme.gold.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }

    private func objective(_ symbol: String, _ count: Int?, _ help: String) -> some View {
        Label("\(count ?? 0)", systemImage: symbol).font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary).help(help)
    }
}

/// Placeholder in the shape of a match card.
struct MatchCardSkeleton: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Bone(width: 58, height: 11, line: 15)
                Bone(width: 74, height: 8, line: 13)
                Bone(width: 42, height: 7, line: 13)
                Bone(width: 52, height: 7, line: 13)
            }
            .frame(width: 104, alignment: .leading)
            HStack(spacing: 4) {
                Bone(width: 50, height: 50, radius: 12)
                VStack(spacing: 3) {
                    Bone(width: 22, height: 22, radius: 5)
                    Bone(width: 22, height: 22, radius: 5)
                }
                .padding(.leading, 4)
                VStack(spacing: 3) {
                    Bone(width: 24, height: 24, radius: 12)
                    Bone(width: 16, height: 16, radius: 8)
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Bone(width: 82, height: 13, line: 19)
                        Bone(width: 54, height: 8, line: 13)
                        Bone(width: 40, height: 7, line: 13)
                    }
                    .frame(width: 108, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        Bone(width: 104, height: 8, line: 13)
                        Bone(width: 92, height: 8, line: 13)
                        Bone(width: 56, height: 7, line: 13)
                    }
                    .frame(width: 118, alignment: .leading)
                    HStack(spacing: 3) {
                        ForEach(0..<6, id: \.self) { _ in Bone(width: 20, height: 20, radius: 5) }
                        Bone(width: 20, height: 20, radius: 5).padding(.leading, 3)
                    }
                }
                HStack(spacing: 5) {
                    Bone(width: 76, height: 18, radius: 9)
                    Bone(width: 64, height: 18, radius: 9)
                }
                .frame(height: 20)
            }
            Spacer(minLength: 8)
            VStack(spacing: 6) {
                Circle().stroke(Theme.skeleton, lineWidth: 3.5).frame(width: 52, height: 52)
                Bone(width: 34, height: 8, line: 16)
            }
            .frame(width: 66)
        }
        .shimmering()
        .padding(.leading, 18).padding(.trailing, 12).padding(.vertical, 12)
        .background(Theme.raised.opacity(0.45), in: shape)
        .overlay(shape.strokeBorder(Theme.hairline))
    }
}

/// Placeholder cards while a match list loads.
struct MatchListSkeleton: View {
    var count = 5

    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { _ in MatchCardSkeleton() }
        }
    }
}

/// Placeholder for both teams while the details of a match load.
private struct MatchDetailSkeleton: View {
    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Bone(width: 54, height: 11, line: 18)
                        Bone(width: 70, height: 7)
                        Spacer()
                        ForEach(0..<5, id: \.self) { _ in Bone(width: 24, height: 9) }
                    }
                    .padding(.bottom, 2)
                    ForEach(0..<5, id: \.self) { row in
                        HStack(spacing: 8) {
                            Bone(width: 30, height: 30, radius: 7)
                            Bone(width: 32, height: 15, radius: 4)
                            Bone(width: 18, height: 18, radius: 9)
                            Bone(width: [118, 92, 136, 104, 84][row], height: 9).frame(width: 170, alignment: .leading)
                            Bone(width: 30, height: 18, radius: 9)
                            Bone(width: 44, height: 9).frame(width: 66, alignment: .leading)
                            Bone(width: 36, height: 8).frame(width: 50, alignment: .leading)
                            Bone(width: 38, height: 8).frame(width: 50, alignment: .leading)
                            Bone(width: 46, height: 8).frame(width: 64, alignment: .leading)
                            HStack(spacing: 2) {
                                ForEach(0..<7, id: \.self) { _ in Bone(width: 20, height: 20, radius: 5) }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 3).padding(.horizontal, 6)
                    }
                }
                .shimmering()
                .padding(10)
                .background(Theme.raised.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            }
            HStack(alignment: .top, spacing: Theme.gap) {
                chart(tr("Damage to champions"), "flame.fill")
                chart(tr("Gold earned"), "dollarsign.circle.fill")
            }
        }
    }

    private func chart(_ title: String, _ symbol: String) -> some View {
        Panel(title: title, symbol: symbol) {
            VStack(spacing: 6) {
                ForEach(0..<10, id: \.self) { row in
                    HStack(spacing: 10) {
                        Bone(width: [70, 58, 76, 64, 52, 72, 60, 66, 56, 62][row], height: 8, line: 13).frame(width: 110, alignment: .leading)
                        GeometryReader { geo in Bone(width: geo.size.width * (1 - Double(row) * 0.085), height: 10, radius: 4) }
                            .frame(height: 10)
                        Bone(width: 32, height: 8).frame(width: 52, alignment: .trailing)
                    }
                }
            }
            .shimmering()
        }
    }
}

extension GamePerformance.Grade {
    var color: Color {
        switch self {
        case .sPlus: Color(hex: 0xFFC94D)
        case .s: Theme.gold
        case .a: Theme.accentBright
        case .b: Theme.text
        case .c: Theme.textSecondary
        case .d: Theme.loss
        }
    }
}

extension GamePerformance.Badge {
    var title: String {
        switch self {
        case .mvp: "MVP"
        case .ace: "ACE"
        case .pentakill: tr("Pentakill")
        case .quadraKill: tr("Quadra kill")
        case .tripleKill: tr("Triple kill")
        case .perfectKDA: tr("Perfect KDA")
        case .legendary: tr("Legendary")
        case .firstBlood: tr("First blood")
        case .topDamage: tr("Top damage")
        case .teamPlayer: tr("Team player")
        case .demolisher: tr("Demolisher")
        case .frontline: tr("Frontline")
        case .topVision: tr("Top vision")
        case .mostCS: tr("Most CS")
        }
    }

    var symbol: String {
        switch self {
        case .mvp: "crown.fill"
        case .ace: "star.fill"
        case .pentakill, .quadraKill: "flame.fill"
        case .tripleKill: "bolt.fill"
        case .perfectKDA: "checkmark.seal.fill"
        case .legendary: "sparkles"
        case .firstBlood: "drop.fill"
        case .topDamage: "burst.fill"
        case .teamPlayer: "person.3.fill"
        case .demolisher: "building.columns.fill"
        case .frontline: "shield.lefthalf.filled"
        case .topVision: "eye.fill"
        case .mostCS: "leaf.fill"
        }
    }

    var tone: Chip.Tone {
        switch self {
        case .mvp, .pentakill, .quadraKill, .legendary: .gold
        case .ace, .tripleKill, .perfectKDA, .topDamage: .accent
        default: .neutral
        }
    }

    var help: String {
        switch self {
        case .mvp: tr("Best performance score in the match")
        case .ace: tr("Best performance on the losing team")
        case .perfectKDA: tr("Kills or assists without a single death")
        case .legendary: tr("8 or more kills in a row without dying")
        case .topDamage: tr("Most damage to champions in the match")
        case .teamPlayer: tr("Took part in 70% or more of your team's kills")
        case .demolisher: tr("Destroyed 3 or more turrets")
        case .frontline: tr("Took the most damage in the match")
        case .topVision: tr("Highest vision score in the match")
        case .mostCS: tr("Most minions and monsters killed in the match")
        default: ""
        }
    }
}

extension HistoryGame {
    var queueTitle: String {
        if gameMode == "PRACTICETOOL" { return tr("Practice Tool") }
        switch queueId {
        case 420: return tr("Ranked Solo")
        case 440: return tr("Ranked Flex")
        case 400: return tr("Normal Draft")
        case 430, 490: return tr("Quickplay")
        case 480: return tr("Swiftplay")
        case 450: return "ARAM"
        case 1700, 1710, 1750: return tr("Arena")
        case 830, 840, 850, 870, 880, 890: return tr("Co-op vs AI")
        default: return gameType == "CUSTOM_GAME" ? tr("Custom game") : (gameMode ?? "").capitalized
        }
    }
}


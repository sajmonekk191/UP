import SwiftUI

/// Latest matches with a performance grade and badges for each game.
struct RecentMatchesPanel: View {
    @Environment(AppModel.self) private var model
    let games: [HistoryGame]
    var showAll: () -> Void

    var body: some View {
        Panel(title: tr("Recent matches"), symbol: "clock.arrow.circlepath") {
            HStack(spacing: 12) {
                if let average { AverageGrade(score: average) }
                Button(action: showAll) {
                    HStack(spacing: 4) {
                        Text(tr("All matches"))
                        Image(systemName: "arrow.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accentBright)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } content: {
            if games.isEmpty {
                Text(tr("No matches yet.")).font(.callout).foregroundStyle(Theme.textSecondary)
            }
            VStack(spacing: 8) {
                ForEach(games) { game in
                    if let me = game.me {
                        MatchCard(game: game, me: me, performance: model.myPerformance[game.id], grading: model.isGrading)
                    }
                }
            }
        }
    }

    private var average: Double? {
        let scores = games.compactMap { model.myPerformance[$0.id]?.score }
        return scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
    }
}

private struct AverageGrade: View {
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
}

/// One match: result, champion, KDA, farm, items, badges and the performance grade.
private struct MatchCard: View {
    let game: HistoryGame
    let me: HistoryParticipant
    let performance: GamePerformance?
    let grading: Bool

    private var tint: Color { !game.isCountable ? Theme.textMuted : me.stats.win == true ? Theme.win : Theme.loss }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 12) {
            result.frame(width: 112, alignment: .leading)
            champion
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 16) {
                    kda.frame(width: 108, alignment: .leading)
                    farm.frame(width: 124, alignment: .leading)
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
                Theme.raised.opacity(0.35)
                LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0.02)], startPoint: .leading, endPoint: .trailing)
                tint.frame(width: 4)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.hairline))
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(resultTitle).font(.callout.weight(.bold)).foregroundStyle(game.isCountable ? tint : Theme.textSecondary)
            Text(game.queueTitle).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1).minimumScaleFactor(0.75)
            Label(formatTime(Double(game.gameDuration ?? 0)), systemImage: "clock")
                .labelStyle(CompactLabel())
                .font(.caption2.monospacedDigit()).foregroundStyle(Theme.textMuted)
            if let date = game.date {
                Text(date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated).locale(Localizer.shared.language.locale)))
                    .font(.caption2).foregroundStyle(Theme.textMuted).lineLimit(1).minimumScaleFactor(0.85)
            }
        }
    }

    private var resultTitle: String {
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
            HStack(spacing: 0) {
                Text("\(s.kills ?? 0)")
                Text(" / ").foregroundStyle(Theme.textMuted)
                Text("\(s.deaths ?? 0)").foregroundStyle(Theme.loss)
                Text(" / ").foregroundStyle(Theme.textMuted)
                Text("\(s.assists ?? 0)")
            }
            .font(.system(size: 16, weight: .bold).monospacedDigit())
            .foregroundStyle(Theme.text)
            Text("\(decimal(s.kda, 2)) KDA").font(.caption.weight(.semibold)).foregroundStyle(kdaColor(s.kda))
            if let kp = performance?.killParticipation {
                Text("KP \(percent(kp, digits: 0))").font(.caption2).foregroundStyle(Theme.textMuted)
            }
        }
    }

    private func kdaColor(_ kda: Double) -> Color {
        kda >= 5 ? Theme.gold : kda >= 3 ? Theme.accentBright : Theme.textSecondary
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
            ForEach(0..<6, id: \.self) { ItemIcon(id: ids[$0], size: 22) }
            ItemIcon(id: ids[6], size: 22).padding(.leading, 3)
        }
    }

    private var badges: some View {
        let shown = Array((performance?.badges ?? []).filter { $0 != .mvp && $0 != .ace }.prefix(3))
        return ViewThatFits(in: .horizontal) {
            chips(shown)
            chips(Array(shown.prefix(2)))
            chips(Array(shown.prefix(1)))
        }
    }

    private func chips(_ list: [GamePerformance.Badge]) -> some View {
        HStack(spacing: 5) {
            ForEach(list, id: \.self) { badge in
                Chip(text: badge.title, tone: badge.tone, symbol: badge.symbol).help(badge.help)
            }
        }
    }
}

private struct CompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
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
                    ProgressView().controlSize(.small)
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
        case 1700, 1710: return tr("Arena")
        case 830, 840, 850, 870, 880, 890: return tr("Co-op vs AI")
        default: return gameType == "CUSTOM_GAME" ? tr("Custom game") : (gameMode ?? "").capitalized
        }
    }
}

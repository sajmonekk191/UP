import SwiftUI

/// How well a player knows the champion they are playing, from mastery and recent games.
struct ChampionExperience {
    enum Level: Int { case firstTime, playedBefore, experienced, veteran, main }

    let level: Level
    let masteryLevel: Int?
    let points: Int
    let games: Int
    let winRate: Double?

    init(profile: PlayerProfile?, championId: Int?) {
        let mastery = profile?.masteries.first { $0.championId == championId }
        let record = championId.flatMap { profile?.record(for: $0) }
        points = mastery?.championPoints ?? 0
        masteryLevel = mastery?.championLevel
        games = record?.games ?? 0
        winRate = record?.winRate
        let recentShare = Double(games) / Double(max(profile?.recentGames.count ?? 0, 1))
        level = switch true {
        case games >= 8 || recentShare >= 0.5: .main
        case points >= 100_000: .veteran
        case points >= 30_000 || games >= 3: .experienced
        case points >= 8_000 || games >= 1: .playedBefore
        default: .firstTime
        }
    }

    var title: String {
        switch level {
        case .main: tr("Main (champion)")
        case .veteran: tr("Veteran")
        case .experienced: tr("Experienced")
        case .playedBefore: tr("Played before")
        case .firstTime: tr("First time?")
        }
    }

    var tone: Chip.Tone {
        switch level {
        case .main, .veteran: .gold
        case .experienced: .accent
        case .playedBefore: .neutral
        case .firstTime: .bad
        }
    }
}

/// Link icon coloured per premade group, so players who queued together stand out.
struct PremadeBadge: View {
    let group: Int

    var body: some View {
        let colors = [Theme.gold, Theme.accentBright, Theme.good, Theme.warning]
        Image(systemName: "link").font(.system(size: 9, weight: .bold))
            .foregroundStyle(colors[(group - 1) % colors.count])
            .help(tr("Premade: played at least two recent games together with the players marked in the same colour."))
    }
}

/// One row of the match overview, joining live game data with the scouted profile.
struct ScoreboardEntry: Identifiable {
    let live: LivePlayer
    let championId: Int?
    let profile: PlayerProfile?
    var id: String { live.id }
    var queue: RankedQueue? { profile?.solo?.isRanked == true ? profile?.solo : profile?.flex?.isRanked == true ? profile?.flex : profile?.solo }
}

/// Large in-game overview of both teams: ranks, games, champion experience, form and live stats.
struct InGameScoreboard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openPlayer) private var openPlayer

    var body: some View {
        if let live = model.live {
            let entries = self.entries(live)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    AppMark(size: 22)
                    Text(tr("Match overview")).font(.headline).foregroundStyle(Theme.text)
                    Text(formatTime(live.gameTime)).font(.callout.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(tr("⇧Tab back to HUD")).font(.caption2).foregroundStyle(Theme.textMuted)
                    MiniHUDToggle()
                    OverlayControls()
                }
                team(tr("Your team"), entries.filter { $0.live.team == live.myTeam }, Theme.ally, live: live)
                team(tr("Enemy team"), entries.filter { $0.live.team != live.myTeam }, Theme.enemy, live: live)
                InsightsRow(live: live, insights: MatchInsights(live: live, hud: model.hud, data: model.gameData))
                if !model.isHUDPreview, entries.contains(where: { $0.profile == nil }) {
                    Label(tr("Loading player data from the client…"), systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption).foregroundStyle(Theme.textMuted)
                }
            }
            .padding(14)
            .frame(width: 1030)
            .background(WindowDragHandle())
            .background(Theme.background.opacity(0.94), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.accent.opacity(0.35)))
        }
    }

    private func entries(_ live: LiveGameSnapshot) -> [ScoreboardEntry] {
        let roster = (model.gameSession?.gameData?.teamOne ?? []) + (model.gameSession?.gameData?.teamTwo ?? [])
        return live.players.map { player in
            let championId = model.gameData.champion(named: player.championName)?.id
            let profile: PlayerProfile? = model.isHUDPreview
                ? HUDPreview.profiles[player.championName]
                : model.profile(for: roster.first { $0.championId == championId }?.puuid)
            return ScoreboardEntry(live: player, championId: championId, profile: profile)
        }
    }

    private func team(_ title: String, _ entries: [ScoreboardEntry], _ color: Color, live: LiveGameSnapshot) -> some View {
        let premades = PlayerProfile.premadeGroups(entries.compactMap(\.profile))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                Label(title, systemImage: "circle.fill").font(.label).textCase(.uppercase).tracking(0.8).foregroundStyle(color)
                    .lineLimit(1).fixedSize()
                let ranked = entries.compactMap { $0.queue }.filter(\.isRanked)
                if let average = averageTier(ranked) {
                    Text(tr("Avg. rank %@", average)).font(.caption).foregroundStyle(Theme.textSecondary)
                }
                let rates = entries.compactMap { $0.profile?.recentWinRate }
                if !rates.isEmpty {
                    let avg = rates.reduce(0, +) / Double(rates.count)
                    Text(tr("Form %@", percent(avg, digits: 0))).font(.caption).foregroundStyle(winRateColor(avg))
                }
                let mains = entries.filter { ChampionExperience(profile: $0.profile, championId: $0.championId).level.rawValue >= ChampionExperience.Level.veteran.rawValue }.count
                if mains > 0 { Chip(text: tr("%d on their main", mains), tone: .gold).fixedSize() }
                let sizes = Dictionary(grouping: premades.values, by: { $0 }).values.map(\.count).sorted(by: >)
                if !sizes.isEmpty { Chip(text: tr("Premades: %@", sizes.map(String.init).joined(separator: " + ")), tone: .neutral, symbol: "link").fixedSize() }
                Spacer()
            }
            header
            ForEach(entries) { row($0, color: color, premade: $0.profile.flatMap { premades[$0.puuid] }) }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 278)
            Text(tr("Rank")).frame(width: 210, alignment: .leading)
            Text(tr("Champion")).frame(width: 190, alignment: .leading)
            Text(tr("Form")).frame(width: 120, alignment: .leading)
            Text(tr("Live · items")).frame(width: 190, alignment: .leading)
        }
        .font(.system(size: 9, weight: .semibold)).textCase(.uppercase).tracking(0.6).foregroundStyle(Theme.textMuted)
    }

    private func row(_ entry: ScoreboardEntry, color: Color, premade: Int?) -> some View {
        let player = entry.live
        let experience = ChampionExperience(profile: entry.profile, championId: entry.championId)
        let queue = entry.queue
        return HStack(spacing: 0) {
            HStack(spacing: 9) {
                ChampionIcon(id: entry.championId, size: 34, ring: color.opacity(0.6))
                    .overlay(alignment: .bottomTrailing) {
                        Text("\(player.level)").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.text)
                            .padding(.horizontal, 3).background(Theme.background, in: RoundedRectangle(cornerRadius: 3)).offset(x: 3, y: 3)
                    }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        if let lane = Lane(clientPosition: player.position) { Image(systemName: lane.symbol).font(.system(size: 9)).foregroundStyle(Theme.textMuted) }
                        let name = Text(player.name).font(.callout.weight(.semibold)).foregroundStyle(player.id == model.live?.me?.id ? Theme.gold : Theme.text).lineLimit(1)
                        if let riotId = player.riotId, riotId.contains("#"), let openPlayer {
                            Button { openPlayer(PlayerQuery(riotId: riotId, region: model.clientRegion ?? model.searchRegion)) } label: { name }
                                .buttonStyle(.plain).handCursor()
                                .help(tr("Open the profile of %@", riotId))
                        } else {
                            name
                        }
                        if let premade { PremadeBadge(group: premade) }
                    }
                    HStack(spacing: 4) {
                        if let level = entry.profile?.summoner?.summonerLevel { Text(tr("Lvl %d", level)).font(.caption2).foregroundStyle(Theme.textMuted) }
                        ForEach(Array((entry.profile?.tags ?? []).prefix(2))) { TagChip(tag: $0).lineLimit(1) }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: 270, alignment: .leading)

            HStack(spacing: 8) {
                RankEmblem(tier: queue?.isRanked == true ? queue?.tier : nil, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(queue?.label ?? tr("Unranked")).font(.caption.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    if let queue, queue.games > 0 {
                        Text(tr("%d games · %@", queue.games, percent(queue.winRate, digits: 0))).font(.caption2).foregroundStyle(winRateColor(queue.winRate))
                    } else {
                        Text(entry.profile == nil ? "…" : tr("No ranked games")).font(.caption2).foregroundStyle(Theme.textMuted)
                    }
                }
            }
            .frame(width: 210, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Chip(text: experience.title, tone: experience.tone)
                HStack(spacing: 6) {
                    if let level = experience.masteryLevel {
                        Text("M\(level) · \(compact(Double(experience.points)))").font(.caption2.weight(.semibold)).foregroundStyle(Theme.gold)
                    }
                    if experience.games > 0 {
                        Text(tr("%d games · %@", experience.games, percent(experience.winRate, digits: 0))).font(.caption2).foregroundStyle(winRateColor(experience.winRate))
                    }
                }
            }
            .frame(width: 190, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                if let profile = entry.profile, !profile.form.isEmpty {
                    FormStrip(form: Array(profile.form.prefix(5)), size: 12)
                    let kda = profile.averageKDA
                    Text("\(decimal(kda.k)) / \(decimal(kda.d)) / \(decimal(kda.a))").font(.caption2.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                } else {
                    Text("—").foregroundStyle(Theme.textMuted)
                }
            }
            .frame(width: 120, alignment: .leading)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(player.scores.kills)/\(player.scores.deaths)/\(player.scores.assists)").font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.text)
                    Text("\(player.scores.creepScore) CS").font(.caption2.monospacedDigit()).foregroundStyle(Theme.textMuted)
                }
                .frame(width: 58, alignment: .leading)
                HStack(spacing: 2) {
                    ForEach(player.items.filter { ($0.slot ?? 0) < 6 }, id: \.self) { ItemIcon(id: $0.itemID, size: 18) }
                }
            }
            .frame(width: 190, alignment: .leading)
        }
        .padding(.vertical, 3).padding(.horizontal, 8)
        .background(player.isDead ? Theme.loss.opacity(0.07) : Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3).clipShape(RoundedRectangle(cornerRadius: 2)) }
    }

    /// Average rank of ranked players, rounded to the nearest tier and division.
    private func averageTier(_ queues: [RankedQueue]) -> String? {
        let tiers = ["IRON", "BRONZE", "SILVER", "GOLD", "PLATINUM", "EMERALD", "DIAMOND", "MASTER", "GRANDMASTER", "CHALLENGER"]
        let divisions = ["IV", "III", "II", "I"]
        let scores = queues.compactMap { q -> Double? in
            guard let t = tiers.firstIndex(of: q.tier ?? "") else { return nil }
            return Double(t * 4 + (divisions.firstIndex(of: q.division ?? "") ?? 0))
        }
        guard !scores.isEmpty else { return nil }
        let mean = Int((scores.reduce(0, +) / Double(scores.count)).rounded())
        let tier = tiers[min(mean / 4, tiers.count - 1)]
        let name = tier.prefix(1) + tier.dropFirst().lowercased()
        return mean / 4 >= 7 ? String(name) : "\(name) \(divisions[mean % 4])"
    }
}

/// Turns the small in-game HUD on or off from the match overview.
private struct MiniHUDToggle: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Button { model.hudClosed.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: model.hudClosed ? "rectangle.slash" : "rectangle.inset.topright.filled")
                    .font(.system(size: 10, weight: .semibold))
                Text(tr("Mini HUD")).font(.caption2.weight(.semibold))
                Circle().fill(model.hudClosed ? Theme.textMuted : Theme.good).frame(width: 6, height: 6)
            }
            .foregroundStyle(model.hudClosed ? Theme.textSecondary : Theme.text)
            .padding(.horizontal, 8).frame(height: 20)
            .background(Theme.raised, in: Capsule())
            .overlay(Capsule().strokeBorder(model.hudClosed ? Theme.hairline : Theme.good.opacity(0.5)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain).handCursor()
        .help(model.hudClosed ? tr("Show the mini HUD") : tr("Hide the mini HUD"))
    }
}

/// Normal-window stage for the HUD preview: a game-like backdrop with the overlay on top.
struct HUDPreviewScene: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [Color(hex: 0x1D2B1F), Color(hex: 0x0E1510)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack {
                Spacer()
                Text(tr("Preview: in a real game this appears only while League of Legends is in front, over the game."))
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
                    .padding(8).background(.black.opacity(0.4), in: Capsule())
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
            ScrollView([.vertical, .horizontal]) {
                InGameStage().padding(20).frame(maxWidth: .infinity, alignment: .topTrailing)
            }
            if model.hudMode == .hud && model.hudClosed {
                VStack(spacing: 8) {
                    Text(tr("Mini HUD hidden. ⇧Tab still opens the match overview.")).font(.callout).foregroundStyle(.white.opacity(0.8))
                    Button(tr("Show the mini HUD")) { model.hudClosed = false }.buttonStyle(.secondary)
                }
                .padding(16).background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1100, minHeight: 720)
        .ignoresSafeArea()
    }
}

/// Build guide, itemization against the enemy team, and the lane matchup with enemy threats.
private struct InsightsRow: View {
    @Environment(AppModel.self) private var model
    let live: LiveGameSnapshot
    let insights: MatchInsights

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            buildGuide.frame(width: 410)
            itemization.frame(width: 300)
            laneAndThreats.frame(maxWidth: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func card<Content: View>(_ title: String, _ symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.label).textCase(.uppercase).tracking(0.8).foregroundStyle(Theme.accentBright)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline))
    }

    private var buildGuide: some View {
        card(tr("Your build path"), "hammer.fill") {
            if insights.steps.isEmpty {
                Text(tr("Loading the build for your champion…")).font(.caption).foregroundStyle(Theme.textMuted)
            } else {
                HStack(spacing: 5) {
                    ForEach(Array(insights.steps.enumerated()), id: \.element.id) { index, step in
                        if index > 0 { Image(systemName: "chevron.right").font(.system(size: 7, weight: .bold)).foregroundStyle(Theme.textMuted) }
                        ItemIcon(id: step.itemId, size: step.state == .next ? 34 : 26)
                            .opacity(step.state == .owned ? 0.45 : 1)
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(step.state == .next ? Theme.gold : .clear, lineWidth: 2))
                            .overlay(alignment: .bottomTrailing) {
                                if step.state == .owned {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 10)).foregroundStyle(Theme.good).offset(x: 3, y: 3)
                                }
                            }
                    }
                }
                if let goal = model.hud.goal {
                    Text(goal.remaining == 0 ? tr("Next: %@, you can buy it now", goal.name) : tr("Next: %@, %d g left", goal.name, goal.remaining))
                        .font(.caption.weight(.semibold)).foregroundStyle(goal.remaining == 0 ? Theme.good : Theme.gold)
                }
                if !insights.skillPriority.isEmpty {
                    HStack(spacing: 4) {
                        Text(tr("Skill max")).font(.caption2).foregroundStyle(Theme.textMuted)
                        ForEach(Array(insights.skillPriority.enumerated()), id: \.offset) { index, key in
                            if index > 0 { Image(systemName: "chevron.right").font(.system(size: 7, weight: .bold)).foregroundStyle(Theme.textMuted) }
                            Text(key).font(.caption.weight(.bold)).foregroundStyle(Theme.text)
                                .frame(width: 20, height: 20).background(Theme.accentDeep, in: RoundedRectangle(cornerRadius: 5))
                        }
                        Text(tr("R at 6 / 11 / 16")).font(.caption2).foregroundStyle(Theme.textMuted).padding(.leading, 4)
                    }
                }
            }
        }
    }

    private var itemization: some View {
        card(tr("Itemize vs enemy"), "shield.checkered") {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(tr("Enemy damage")).font(.caption2).foregroundStyle(Theme.textMuted)
                    Spacer()
                    Text(tr("%@ magic", percent(insights.enemyMagicShare, digits: 0))).font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                }
                Meter(value: insights.enemyMagicShare, tint: Color(hex: 0x9B7BFF), track: Color(hex: 0xE0874A).opacity(0.55), height: 5)
            }
            if insights.suggestions.isEmpty {
                Text(tr("No special counter items needed right now.")).font(.caption).foregroundStyle(Theme.textMuted)
            }
            ForEach(insights.suggestions.prefix(4)) { suggestion in
                HStack(spacing: 8) {
                    ItemIcon(id: suggestion.itemId, size: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.gameData.items[suggestion.itemId]?.name ?? "").font(.caption.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        Text(suggestion.reason).font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                }
            }
        }
    }

    private var laneAndThreats: some View {
        card(tr("Lane & threats"), "exclamationmark.triangle.fill") {
            if let opponent = insights.opponentId {
                HStack(spacing: 8) {
                    ChampionIcon(id: opponent, size: 26, ring: Theme.enemy.opacity(0.6))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tr("vs %@", model.gameData.championName(opponent))).font(.caption.weight(.semibold)).foregroundStyle(Theme.text)
                        Text(insights.matchupWinRate.map { tr("%@ win rate in this matchup", percent($0)) } ?? tr("Not enough matchup data"))
                            .font(.caption2).foregroundStyle(winRateColor(insights.matchupWinRate))
                    }
                }
                if let tip = insights.matchupTip {
                    Text(tip).font(.caption2).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if insights.threats.isEmpty {
                Text(tr("No enemy is ahead right now.")).font(.caption).foregroundStyle(Theme.textMuted)
            }
            ForEach(insights.threats.prefix(3)) { threat in
                HStack(spacing: 8) {
                    ChampionIcon(id: threat.championId, size: 22)
                    Text("\(threat.name): ").font(.caption2.weight(.semibold)).foregroundColor(Theme.text) + Text(threat.detail).font(.caption2).foregroundColor(Theme.textSecondary)
                }
            }
        }
    }
}

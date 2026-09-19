import AppKit
import SwiftUI

/// Opens the champ select window when a draft starts and closes it when the draft ends.
@MainActor
final class ChampSelectWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model: AppModel
    private var wasInChampSelect = false

    init(model: AppModel) {
        self.model = model
        super.init()
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = model.isInChampSelect
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.sync()
                self?.observe()
            }
        }
    }

    private func sync() {
        let inDraft = model.isInChampSelect
        defer { wasInChampSelect = inDraft }
        if inDraft, !wasInChampSelect, model.settings.autoOpenChampSelect || model.isPreview { show() }
        if !inDraft { window?.close() }
    }

    func show() {
        let window = self.window ?? makeWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1360, height: 880),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "UP! – Champ Select"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Theme.background)
        window.minSize = NSSize(width: 1240, height: 760)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("UPChampSelect")
        window.contentView = NSHostingView(rootView: ChampSelectWindowView().environment(model))
        window.center()
        window.delegate = self
        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        if model.isPreview { model.endPreview() }
    }
}

struct ChampSelectWindowView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Theme.background
            Theme.backdrop.frame(height: 320).frame(maxHeight: .infinity, alignment: .top)
            if let session = model.champSelect {
                VStack(spacing: 0) {
                    DraftHeader(session: session)
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                    HStack(spacing: 0) {
                        TeamRail(session: session)
                        Rectangle().fill(Theme.hairline).frame(width: 1)
                        DraftMain(session: session)
                    }
                }
            } else {
                EmptyState(symbol: "person.2.fill", title: tr("Waiting for champ select"),
                           message: tr("This window opens by itself as soon as champ select starts."))
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }
}

// MARK: - Header

private struct DraftHeader: View {
    @Environment(AppModel.self) private var model
    let session: ChampSelectSession

    var body: some View {
        HStack(spacing: 16) {
            AppMark(size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("Champ Select")).font(.title2.weight(.bold)).foregroundStyle(Theme.text)
                HStack(spacing: 6) {
                    if let lane = model.advisor.lane { Chip(text: tr("You: %@", lane.title), tone: .accent, symbol: lane.symbol) }
                    Chip(text: model.queueMode.title, tone: .neutral)
                    if model.isPreview { Chip(text: tr("Preview"), tone: .gold, symbol: "eye") }
                }
            }
            Spacer()
            if let action = session.myActiveAction {
                Label(action.type == "ban" ? tr("Your turn to ban") : tr("Your turn to pick"), systemImage: action.type == "ban" ? "nosign" : "hand.point.up.left.fill")
                    .font(.headline).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(LinearGradient(colors: [Theme.accentBright, Theme.accent], startPoint: .top, endPoint: .bottom), in: Capsule())
                    .shadow(color: Theme.accent.opacity(0.5), radius: 12)
            }
            if model.isPreview {
                if model.advisor.focusChampion == nil {
                    Button(tr("Hover top pick")) { model.previewHover() }.buttonStyle(.primary)
                } else if !model.advisor.focusLocked {
                    Button(tr("Lock in (preview)")) { model.previewLock() }.buttonStyle(.primary)
                }
                Button(tr("End preview")) { model.endPreview() }.buttonStyle(.secondary)
            }
            if let timer = session.timer {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let left = remaining(timer)
                    Text("\(left)s").font(.system(size: 26, weight: .semibold).monospacedDigit())
                        .foregroundStyle(left <= 10 ? Theme.loss : Theme.text)
                        .frame(width: 70, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 24).padding(.top, 34).padding(.bottom, 14)
    }

    private func remaining(_ timer: ChampSelectTimer) -> Int {
        guard let left = timer.adjustedTimeLeftInPhase, let now = timer.internalNowInEpochMs else { return 0 }
        return max(Int((left - (Date().timeIntervalSince1970 * 1000 - now)) / 1000), 0)
    }
}

// MARK: - Team rail

private struct TeamRail: View {
    @Environment(AppModel.self) private var model
    let session: ChampSelectSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Your team")).eyebrow()
                    ForEach(session.myTeam) { player in allyRow(player) }
                }
                if let enemies = session.theirTeam, !enemies.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("Enemy team")).eyebrow()
                        ForEach(enemies) { enemy in enemyRow(enemy) }
                    }
                }
                let bans = completedBans
                if !bans.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("Bans")).eyebrow()
                        HStack(spacing: 4) {
                            ForEach(bans, id: \.id) { ban in
                                ChampionIcon(id: ban.championId, size: 30).grayscale(1).opacity(0.7)
                                    .overlay(Rectangle().fill(Theme.loss).frame(height: 2).rotationEffect(.degrees(-45)))
                            }
                        }
                    }
                }
                MyFormCard()
            }
            .frame(width: 278, alignment: .leading)
            .padding(16)
        }
        .defaultScrollAnchor(.top)
        .frame(width: 310)
        .background(Theme.sidebar.opacity(0.7))
    }

    private var completedBans: [ChampSelectAction] {
        let all: [ChampSelectAction] = (session.actions ?? []).flatMap { $0 }
        return all.filter { (a: ChampSelectAction) -> Bool in a.type == "ban" && a.completed == true && (a.championId ?? 0) > 0 }
    }

    private func allyRow(_ player: ChampSelectPlayer) -> some View {
        let isMe = player.cellId == session.localPlayerCellId
        let profile = model.profile(for: player.puuid)
        let queue = profile?.solo?.isRanked == true ? profile?.solo : profile?.flex
        return HStack(spacing: 10) {
            ChampionIcon(id: player.displayedChampionId, size: 40, ring: isMe ? Theme.gold : Theme.ally.opacity(0.5))
                .opacity((player.championId ?? 0) == 0 && player.displayedChampionId > 0 ? 0.6 : 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if let lane = Lane(clientPosition: player.assignedPosition) {
                        Image(systemName: lane.symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textMuted)
                    }
                    Text(profile?.summoner?.gameName ?? (player.hasIdentity ? player.gameName ?? "" : tr("Hidden"))).font(.callout.weight(.semibold))
                        .foregroundStyle(isMe ? Theme.gold : Theme.text).lineLimit(1)
                }
                if let profile {
                    HStack(spacing: 6) {
                        Text(queue?.label ?? tr("Unranked")).font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        FormStrip(form: Array(profile.form.prefix(5)), size: 14)
                    }
                    if let first = profile.tags.first { TagChip(tag: first).lineLimit(1) }
                } else {
                    Text(model.gameData.championName(player.displayedChampionId)).font(.caption2).foregroundStyle(Theme.textMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(isMe ? Theme.gold.opacity(0.07) : Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(isMe ? Theme.gold.opacity(0.4) : Theme.hairline))
    }

    private func enemyRow(_ enemy: ChampSelectPlayer) -> some View {
        let id = enemy.displayedChampionId
        let isOpponent = id > 0 && id == model.advisor.laneOpponent
        return HStack(spacing: 10) {
            ChampionIcon(id: id > 0 ? id : nil, size: 34, ring: Theme.enemy.opacity(0.6))
            Text(id > 0 ? model.gameData.championName(id) : tr("Picking…")).font(.callout).foregroundStyle(id > 0 ? Theme.text : Theme.textMuted)
            Spacer()
            if isOpponent { Chip(text: tr("Your lane"), tone: .bad) }
        }
        .padding(6)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(isOpponent ? Theme.enemy.opacity(0.5) : Theme.hairline))
    }
}

private struct MyFormCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let profile = model.myProfile {
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("Your form")).eyebrow()
                HStack {
                    RankEmblem(tier: profile.solo?.isRanked == true ? profile.solo?.tier : nil, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.solo?.label ?? tr("Unranked")).font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                        Text(tr("%@ recent win rate", percent(profile.recentWinRate, digits: 0))).font(.caption).foregroundStyle(winRateColor(profile.recentWinRate))
                    }
                }
                FormStrip(form: Array(profile.form.prefix(10)), size: 14)
                if let best = profile.champions.filter({ $0.games >= 2 }).max(by: { $0.winRate < $1.winRate }) {
                    HStack(spacing: 6) {
                        ChampionIcon(id: best.championId, size: 22)
                        Text(tr("Best recent: %@ (%@)", model.gameData.championName(best.championId), percent(best.winRate, digits: 0)))
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelBackground(Theme.surface, radius: 12)
        }
    }
}

// MARK: - Main area

private struct DraftMain: View {
    @Environment(AppModel.self) private var model
    let session: ChampSelectSession
    @State private var previewChampion: Int?

    var body: some View {
        let advisor = model.advisor
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                if let champion = advisor.focusChampion {
                    if advisor.focusLocked {
                        LockedView(championId: champion)
                    } else {
                        HoverView(championId: champion)
                        PickAdvisorPanel(selected: $previewChampion)
                    }
                } else {
                    if model.queueMode == .aram {
                        Panel(title: "ARAM", symbol: "dice.fill") {
                            Text(tr("Pick suggestions are for Summoner's Rift. Your runes load as soon as you get a champion.")).foregroundStyle(Theme.textSecondary)
                        }
                    } else {
                        PickAdvisorPanel(selected: $previewChampion)
                    }
                    if let preview = previewChampion { QuickBuild(championId: preview, title: tr("Preview")) }
                    HStack(alignment: .top, spacing: Theme.gap) {
                        BanPanel()
                        CompositionPanel()
                    }
                    .environment(\.panelFillsHeight, true)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
        }
        .defaultScrollAnchor(.top)
    }
}

/// Ranked list of recommended picks with reasons.
private struct PickAdvisorPanel: View {
    @Environment(AppModel.self) private var model
    @Binding var selected: Int?

    var body: some View {
        let advisor = model.advisor
        Panel(title: tr("Best picks for you"), symbol: "sparkles") {
            if model.queueMode == .ranked {
                Segmented(options: Lane.allCases.map { ($0, $0.title) },
                          selection: Binding(get: { advisor.lane ?? .middle }, set: { lane in
                              advisor.laneOverride = lane
                              if let session = model.champSelect { advisor.update(session, model: model) }
                          }))
            }
        } content: {
            if advisor.loadingSuggestions && advisor.suggestions.isEmpty {
                HStack { ProgressView().controlSize(.small); Text(tr("Analysing matchups…")).foregroundStyle(Theme.textSecondary) }
            }
            ForEach(Array(advisor.suggestions.prefix(8).enumerated()), id: \.element.id) { index, pick in
                if index > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                Button { selected = selected == pick.championId ? nil : pick.championId } label: {
                    PickRow(pick: pick, rank: index + 1, selected: selected == pick.championId)
                }
                .buttonStyle(.plain)
            }
            Text(tr("Score combines tier, counters against revealed enemies, your mastery and results, and team fit. Only champions you own."))
                .font(.caption2).foregroundStyle(Theme.textMuted)
        }
    }
}

private struct PickRow: View {
    @Environment(AppModel.self) private var model
    let pick: PickSuggestion
    let rank: Int
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)").font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(Theme.textMuted).frame(width: 16)
            ChampionIcon(id: pick.championId, size: 44, ring: rank == 1 ? Theme.gold : nil)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(model.gameData.championName(pick.championId)).font(.headline).foregroundStyle(Theme.text)
                    ForEach(pick.matchups.prefix(4), id: \.enemyId) { m in
                        HStack(spacing: 3) {
                            ChampionIcon(id: m.enemyId, size: 16)
                            Text(percent(m.winRate, digits: 0)).font(.caption2.monospacedDigit()).foregroundStyle(winRateColor(m.winRate))
                        }
                        .help(tr("Win rate vs %@", model.gameData.championName(m.enemyId)))
                    }
                }
                HStack(spacing: 4) {
                    ForEach(pick.reasons.prefix(4)) { reason in
                        Chip(text: reason.text, tone: reason.positive ? .accent : .bad)
                    }
                }
            }
            Spacer()
            ScoreRing(score: pick.score)
        }
        .padding(.vertical, 4).padding(.horizontal, 4)
        .background(selected ? Theme.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }
}

struct ScoreRing: View {
    let score: Int

    var body: some View {
        let color = score >= 65 ? Theme.accentBright : score >= 50 ? Theme.text : Theme.loss
        ZStack {
            Circle().stroke(Theme.accentTrack, lineWidth: 4)
            Circle().trim(from: 0, to: CGFloat(score) / 100)
                .stroke(score >= 50 ? Theme.accent : Theme.loss, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)").font(.callout.weight(.bold).monospacedDigit()).foregroundStyle(color)
        }
        .frame(width: 42, height: 42)
        .help(tr("Fit score out of 100"))
    }
}

private struct BanPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Panel(title: tr("Ban suggestions"), symbol: "nosign") {
            if model.advisor.bans.isEmpty { Text(tr("Loading…")).foregroundStyle(Theme.textMuted) }
            ForEach(model.advisor.bans) { ban in
                HStack(spacing: 10) {
                    ChampionIcon(id: ban.championId, size: 32, ring: Theme.enemy.opacity(0.5))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.gameData.championName(ban.championId)).font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                        Text(ban.reason).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                    Spacer()
                    if ban.winRate > 0 { Text(percent(ban.winRate)).font(.caption.monospacedDigit()).foregroundStyle(winRateColor(ban.winRate)) }
                }
            }
        }
    }
}

private struct CompositionPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let ally = model.advisor.ally, enemy = model.advisor.enemy
        Panel(title: tr("Team composition"), symbol: "person.3.sequence.fill") {
            if ally.count + enemy.count == 0 {
                Text(tr("Appears as champions are picked.")).foregroundStyle(Theme.textMuted)
            } else {
                HStack {
                    Label(tr("Your team"), systemImage: "circle.fill").foregroundStyle(Theme.ally)
                    Spacer()
                    Label(tr("Enemy"), systemImage: "circle.fill").foregroundStyle(Theme.enemy)
                }
                .font(.caption.weight(.semibold))
                VersusBar(label: tr("Magic damage"), ally: ally.magicShare * 100, enemy: enemy.magicShare * 100) { percent($0 / 100, digits: 0) }
                VersusBar(label: tr("Frontline"), ally: ally.frontline, enemy: enemy.frontline) { String(format: "%.0f", $0) }
                VersusBar(label: tr("Crowd control"), ally: ally.crowdControl, enemy: enemy.crowdControl) { String(format: "%.0f", $0) }
                VersusBar(label: tr("Mobility"), ally: ally.mobility, enemy: enemy.mobility) { String(format: "%.0f", $0) }
            }
            ForEach(model.advisor.compTips) { TipRow(tip: $0) }
        }
    }
}

struct TipRow: View {
    let tip: Tip

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tip.symbol).font(.callout).frame(width: 18)
                .foregroundStyle(tip.tone == .good ? Theme.good : tip.tone == .warning ? Theme.warning : Theme.accentBright)
            Text(tip.text).font(.callout).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Focus states

/// Hovered champion: fit, matchups and the top rune pages to import right away.
private struct HoverView: View {
    @Environment(AppModel.self) private var model
    let championId: Int

    var body: some View {
        let advisor = model.advisor
        VStack(alignment: .leading, spacing: Theme.gap) {
            FocusBanner(championId: championId, subtitle: tr("Hovering · lock in to see the full game plan"))
            if advisor.loadingFocus && advisor.builds.isEmpty { ProgressView().controlSize(.small) }
            let runes = [advisor.builds[.emeraldPlus]?.runes.first, advisor.builds[.masterPlus]?.runes.first, advisor.riotRunes.first].compactMap { $0 }
            Panel(title: tr("Quick runes"), symbol: "circle.hexagongrid.fill") {
                ForEach(Array(runes.enumerated()), id: \.element.id) { index, setup in
                    if index > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    RuneRow(setup: setup, recommended: index == 0, compact: true) { Task { await model.applyRunes(setup, championId: championId) } }
                }
                if runes.isEmpty && !advisor.loadingFocus { Text(tr("No data.")).foregroundStyle(Theme.textMuted) }
            }
            VersusEnemies(championId: championId)
        }
    }
}

/// Locked champion: game plan and the full build per elo bracket.
private struct LockedView: View {
    @Environment(AppModel.self) private var model
    let championId: Int
    @State private var tier: EloTier = .emeraldPlus

    var body: some View {
        let advisor = model.advisor
        VStack(alignment: .leading, spacing: Theme.gap) {
            FocusBanner(championId: championId, subtitle: model.isPreview ? tr("Locked in · preview, nothing is sent to the client") : tr("Locked in · runes, spells and items were sent to the client"))
            if !advisor.gamePlan.isEmpty {
                Panel(title: tr("Game plan"), symbol: "map.fill") {
                    ForEach(advisor.gamePlan) { TipRow(tip: $0) }
                }
            }
            VersusEnemies(championId: championId)
            HStack {
                Text(tr("Build by elo")).font(.title3.weight(.bold)).foregroundStyle(Theme.text)
                Spacer()
                Segmented(options: EloTier.allCases.filter { advisor.builds[$0] != nil }.map { ($0, $0.title) }, selection: $tier)
            }
            if advisor.loadingFocus && advisor.builds.isEmpty { ProgressView().controlSize(.small) }
            BuildDetails(build: advisor.builds[tier] ?? advisor.build, extraRunes: tier == .emeraldPlus ? advisor.riotRunes : [], championId: championId)
        }
    }
}

private struct FocusBanner: View {
    @Environment(AppModel.self) private var model
    let championId: Int
    let subtitle: String

    var body: some View {
        let pick = model.advisor.suggestions.first { $0.championId == championId }
        HeroBanner(splashPath: model.gameData.details[championId]?.splashPath, height: 170) {
            HStack(alignment: .bottom, spacing: 16) {
                ChampionIcon(id: championId, size: 64, ring: Theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.gameData.championName(championId)).font(.system(size: 32, weight: .bold)).foregroundStyle(Theme.text)
                    Text(subtitle).font(.callout).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if let build = model.advisor.build {
                    HStack(spacing: 22) {
                        KeyValue(key: tr("Win rate"), value: percent(build.winRate), color: winRateColor(build.winRate))
                        KeyValue(key: tr("Tier"), value: tierName(build.tier), color: (build.tier ?? 5) <= 1 ? Theme.gold : Theme.text)
                        if let record = model.myProfile?.record(for: championId) {
                            KeyValue(key: tr("You"), value: tr("%d games · %@", record.games, percent(record.winRate, digits: 0)), color: winRateColor(record.winRate))
                        }
                    }
                }
                if let pick { ScoreRing(score: pick.score) }
            }
        }
    }
}

/// Matchup win rates of the focused champion against every revealed enemy.
private struct VersusEnemies: View {
    @Environment(AppModel.self) private var model
    let championId: Int

    var body: some View {
        let enemies = model.advisor.enemy.champions
        if !enemies.isEmpty, let build = model.advisor.build {
            Panel(title: tr("Versus enemy team"), symbol: "figure.fencing") {
                HStack(spacing: 12) {
                    ForEach(enemies, id: \.self) { enemyId in
                        let m = build.counters.first { $0.championId == enemyId }
                        VStack(spacing: 6) {
                            ChampionIcon(id: enemyId, size: 44, ring: enemyId == model.advisor.laneOpponent ? Theme.enemy : nil)
                            Text(model.gameData.championName(enemyId)).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                            Text(m.map { percent($0.winRate, digits: 1) } ?? "—").font(.callout.weight(.semibold).monospacedDigit())
                                .foregroundStyle(winRateColor(m?.winRate))
                            if enemyId == model.advisor.laneOpponent { Chip(text: tr("Lane"), tone: .bad) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Text(tr("Win rate of %@ in games against each champion (same role data from op.gg; “—” means too few games).", model.gameData.championName(championId)))
                    .font(.caption2).foregroundStyle(Theme.textMuted)
            }
        }
    }
}

/// Compact build for a suggestion clicked before hovering.
private struct QuickBuild: View {
    @Environment(AppModel.self) private var model
    let championId: Int
    let title: String
    @State private var build: ChampionBuild?

    var body: some View {
        Panel(title: "\(title): \(model.gameData.championName(championId))", symbol: "eye") {
            if let build {
                ForEach(build.runes.prefix(2)) { setup in
                    RuneRow(setup: setup, compact: true) { Task { await model.applyRunes(setup, championId: championId) } }
                }
                if let core = build.coreItems.first {
                    HStack(spacing: 6) {
                        Text(tr("Core")).eyebrow()
                        ForEach(core.ids, id: \.self) { ItemIcon(id: $0, size: 28) }
                        if let skill = build.skillOrder { Text(skill.priority.joined(separator: " › ")).font(.callout.weight(.semibold)).foregroundStyle(Theme.text).padding(.leading, 12) }
                    }
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: championId) {
            build = try? await BuildService.opggBuild(championId: championId, lane: model.advisor.lane, mode: model.queueMode)
        }
    }
}

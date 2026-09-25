import AppKit
import SwiftUI

/// Opens the champ select window when a draft starts and closes it when the draft ends.
@MainActor
final class ChampSelectWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var lastFrame: NSRect?
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
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1360, height: 880),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "UP! – " + tr("Champ select")
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Theme.background)
        window.minSize = NSSize(width: 1240, height: 760)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("UPChampSelect")
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        let hosting = NSHostingView(rootView: ChampSelectWindowView().environment(model))
        hosting.sizingOptions = []
        window.contentView = hosting
        if let lastFrame { window.setFrame(lastFrame, display: false) } else { window.center() }
        window.delegate = self
        self.window = window
        return window
    }

    /// The window is rebuilt for each draft, so its views stop observing the model and free their memory in between.
    func windowWillClose(_ notification: Notification) {
        if model.isPreview { model.endPreview() }
        lastFrame = window?.frame
        window?.contentView = nil
        window = nil
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
                Segmented(options: [QueueMode.ranked, .aram, .arena].map { ($0, $0.title) },
                          selection: Binding(get: { model.previewMode }, set: { model.startPreview(mode: $0) }))
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
        let premades = PlayerProfile.premadeGroups(session.myTeam.compactMap { model.profile(for: $0.puuid) })
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Your team")).eyebrow()
                    ForEach(session.myTeam) { player in allyRow(player, premade: player.puuid.flatMap { premades[$0] }) }
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

    private func allyRow(_ player: ChampSelectPlayer, premade: Int?) -> some View {
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
                    if let premade { PremadeBadge(group: premade) }
                }
                if let profile {
                    HStack(spacing: 6) {
                        Text(queue?.label ?? tr("Unranked")).font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        FormStrip(form: Array(profile.form.prefix(5)), size: 14)
                    }
                    if let first = profile.tags.first { TagChip(tag: first).lineLimit(1) }
                } else if model.settings.scoutTeam, player.hasIdentity {
                    HStack(spacing: 6) {
                        Bone(width: 64, height: 7)
                        HStack(spacing: 3) {
                            ForEach(0..<5, id: \.self) { _ in Bone(width: 14, height: 14, radius: 4) }
                        }
                    }
                    .shimmering()
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
        if model.myProfile == nil, model.connection == .connected {
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("Your form")).eyebrow()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Bone(width: 34, height: 34, radius: 17)
                        VStack(alignment: .leading, spacing: 4) {
                            Bone(width: 96, height: 10, line: 15)
                            Bone(width: 118, height: 7, line: 13)
                        }
                    }
                    HStack(spacing: 3) {
                        ForEach(0..<10, id: \.self) { _ in Bone(width: 14, height: 14, radius: 4) }
                    }
                }
                .shimmering()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelBackground(Theme.surface, radius: 12)
        } else if let profile = model.myProfile {
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
                if profile.streak <= -3 {
                    Label(tr("%d losses in a row. A short break before the next game usually helps.", -profile.streak), systemImage: "cup.and.saucer.fill")
                        .font(.caption).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true)
                }
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
                    if session.benchEnabled != true { PickAdvisorPanel(selected: $previewChampion) }
                    if let preview = previewChampion { QuickBuild(championId: preview, title: tr("Preview")) }
                    HStack(alignment: .top, spacing: Theme.gap) {
                        if (session.actions ?? []).joined().contains(where: { $0.type == "ban" }) { BanPanel() }
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
                LoadingNote(text: tr("Analysing matchups…"))
                ForEach(0..<4, id: \.self) { index in
                    if index > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    PickRowSkeleton()
                }
            }
            ForEach(Array(advisor.suggestions.prefix(8).enumerated()), id: \.element.id) { index, pick in
                if index > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                Button { selected = selected == pick.championId ? nil : pick.championId } label: {
                    PickRow(pick: pick, rank: index + 1, selected: selected == pick.championId)
                }
                .buttonStyle(.plain).handCursor()
            }
            Text(footnote).font(.caption2).foregroundStyle(Theme.textMuted)
        }
    }
}

private extension PickAdvisorPanel {
    var footnote: String {
        switch model.queueMode {
        case .ranked: tr("Score combines tier, counters against revealed enemies, your mastery and results, and team fit. Only champions you own.")
        case .arena: tr("Score combines Arena tier, how well the champion does alongside your teammates' picks, and your mastery and results. Only champions you own.")
        default: tr("Score combines the champion's strength in %@, your mastery and results, and team fit. Only champions you own.", model.queueMode.title)
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

/// Placeholder in the shape of a pick suggestion row.
private struct PickRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            Bone(width: 9, height: 9).frame(width: 16)
            Bone(width: 44, height: 44, radius: 10.5)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Bone(width: 88, height: 12, line: 17)
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 3) {
                            Bone(width: 16, height: 16, radius: 4)
                            Bone(width: 22, height: 7)
                        }
                    }
                }
                HStack(spacing: 4) {
                    Bone(width: 96, height: 16, radius: 8)
                    Bone(width: 82, height: 16, radius: 8)
                    Bone(width: 68, height: 16, radius: 8)
                }
            }
            Spacer()
            Circle().stroke(Theme.skeleton, lineWidth: 4).frame(width: 42, height: 42)
        }
        .padding(.vertical, 4).padding(.horizontal, 4)
        .shimmering()
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
            if model.advisor.bans.isEmpty {
                if model.advisor.loadingSuggestions {
                    RowsSkeleton(rows: 3, icon: 32, trailing: 40)
                } else {
                    Text(tr("No data.")).foregroundStyle(Theme.textMuted)
                }
            }
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
        VStack(alignment: .leading, spacing: Theme.gap) {
            FocusBanner(championId: championId, subtitle: tr("Hovering · lock in to see the full game plan"))
            if model.queueMode != .arena { quickRunes }
            VersusEnemies(championId: championId)
        }
    }

    private var quickRunes: some View {
        let advisor = model.advisor
        let runes = [advisor.builds[.emeraldPlus]?.runes.first, advisor.builds[.masterPlus]?.runes.first, advisor.riotRunes.first].compactMap { $0 }
        return Panel(title: tr("Quick runes"), symbol: "circle.hexagongrid.fill") {
            ForEach(Array(runes.enumerated()), id: \.element.id) { index, setup in
                if index > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                RuneRow(setup: setup, recommended: index == 0, compact: true) { Task { await model.applyRunes(setup, championId: championId) } }
            }
            if runes.isEmpty {
                if advisor.loadingFocus {
                    ForEach(0..<3, id: \.self) { index in
                        if index > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                        RuneRowSkeleton(compact: true)
                    }
                } else {
                    Text(tr("No data.")).foregroundStyle(Theme.textMuted)
                }
            }
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
            FocusBanner(championId: championId, subtitle: subtitle)
            if !advisor.bench.isEmpty { BenchPanel() }
            if !advisor.gamePlan.isEmpty {
                Panel(title: tr("Game plan"), symbol: "map.fill") {
                    ForEach(advisor.gamePlan) { TipRow(tip: $0) }
                }
            }
            VersusEnemies(championId: championId)
            if advisor.builds.count > 1 {
                HStack {
                    Text(tr("Build by elo")).font(.title3.weight(.bold)).foregroundStyle(Theme.text)
                    Spacer()
                    Segmented(options: EloTier.allCases.filter { advisor.builds[$0] != nil }.map { ($0, $0.title) }, selection: $tier)
                }
            }
            if advisor.loadingFocus && advisor.builds.isEmpty {
                BuildSkeleton()
            } else {
                BuildDetails(build: advisor.builds[tier] ?? advisor.build, extraRunes: tier == .emeraldPlus ? advisor.riotRunes : [], championId: championId)
            }
        }
    }

    private var subtitle: String {
        if model.isPreview { return tr("Locked in · preview, nothing is sent to the client") }
        return model.queueMode == .arena ? tr("Locked in · the item set was sent to the client") : tr("Locked in · runes, spells and items were sent to the client")
    }
}

/// Your champion and the bench of an all-random draft, strongest in the mode first, each one click away.
private struct BenchPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let options = model.advisor.bench
        let mine = options.first { $0.isYours }
        let session = model.champSelect
        Panel(title: tr("Bench"), symbol: "arrow.left.arrow.right") {
            if session?.allowRerolling == true, let left = session?.rerollsRemaining, left > 0 {
                Button { Task { await model.reroll() } } label: { Label(tr("Reroll (%d left)", left), systemImage: "dice.fill") }
                    .buttonStyle(.secondary)
            }
        } content: {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                if index > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                row(option, stronger: !option.isYours && (option.entry?.rank ?? 999) < (mine?.entry?.rank ?? 999))
            }
            Text(tr("Ranked by op.gg's %@ tier list. Taking a champion puts yours on the bench.", model.queueMode.title))
                .font(.caption2).foregroundStyle(Theme.textMuted)
        }
    }

    private func row(_ option: BenchOption, stronger: Bool) -> some View {
        HStack(spacing: 12) {
            ChampionIcon(id: option.championId, size: 40, ring: option.isYours ? Theme.gold : stronger ? Theme.accent : nil)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.gameData.championName(option.championId)).font(.headline).foregroundStyle(Theme.text)
                    if option.isYours { Chip(text: tr("You"), tone: .gold) } else if stronger { Chip(text: tr("Stronger than yours"), tone: .accent) }
                }
                HStack(spacing: 8) {
                    if let entry = option.entry {
                        Text(tierName(entry.tier)).font(.caption.weight(.heavy))
                            .foregroundStyle(entry.tier <= 1 ? Theme.gold : entry.tier == 2 ? Theme.accentBright : Theme.textSecondary)
                        Text(tr("%@ WR · #%d", percent(entry.winRate), entry.rank)).font(.caption.monospacedDigit()).foregroundStyle(winRateColor(entry.winRate))
                    }
                    if option.personalGames > 0 {
                        Text(tr("You: %@", tr("%d games · %@", option.personalGames, percent(option.personalWinRate, digits: 0))))
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            Spacer()
            if !option.isYours {
                Button { Task { await model.takeFromBench(option.championId) } } label: { Label(tr("Take"), systemImage: "arrow.down.to.line") }
                    .buttonStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
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
                ForEach(0..<2, id: \.self) { _ in RuneRowSkeleton(compact: true) }
                HStack(spacing: 6) {
                    Text(tr("Core")).eyebrow()
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { _ in Bone(width: 28, height: 28, radius: 5) }
                    }
                    .shimmering()
                }
            }
        }
        .task(id: championId) {
            build = nil
            build = try? await BuildService.opggBuild(championId: championId, lane: model.advisor.lane, mode: model.queueMode)
        }
    }
}

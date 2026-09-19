import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Shows the in-game HUD while the League game (or the HUD itself) is in front; ⌃⇧H toggles it, ⇧Tab switches to the match overview.
@MainActor
final class InGameHUDController {
    static let gameBundleId = "com.riotgames.LeagueofLegends.GameClient"

    private let model: AppModel
    private var panel: NSPanel?
    private var hosting: NSHostingView<AnyView>?
    private var gameIsFrontmost = false
    private var hotKeys: [EventHotKeyRef?] = []
    private var overviewHotKey: EventHotKeyRef?
    private var previewWindow: NSWindow?
    private var fittedMode: HUDMode = .hud
    private var movingProgrammatically = false

    /// Top-left corner per mode; only changed by the user dragging the panel, kept across launches.
    private func anchor(for mode: HUDMode) -> NSPoint? {
        let key = mode == .hud ? "hudAnchor" : "overviewAnchor"
        let d = UserDefaults.standard
        guard d.object(forKey: key + "X") != nil else { return nil }
        return NSPoint(x: d.double(forKey: key + "X"), y: d.double(forKey: key + "Y"))
    }

    private func setAnchor(_ point: NSPoint?, for mode: HUDMode) {
        let key = mode == .hud ? "hudAnchor" : "overviewAnchor"
        UserDefaults.standard.set(point?.x, forKey: key + "X")
        UserDefaults.standard.set(point?.y, forKey: key + "Y")
    }

    init(model: AppModel) {
        self.model = model
        observeModel()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.frontmostChanged(app) }
        }
        frontmostChanged(NSWorkspace.shared.frontmostApplication)
        registerHotKeys()
    }

    private func observeModel() {
        withObservationTracking {
            _ = model.live?.gameTime
            _ = model.isHUDPreview
            _ = model.hudMode
            _ = model.hudClosed
            _ = model.hud.toasts
            _ = model.settings.showOverlay
            _ = model.settings.hudCompact
            _ = model.settings.hudScale
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.observeModel()
            }
        }
        update()
    }

    /// Clicking the HUD activates UP!, so UP! counts as "in game" unless one of its regular windows took focus.
    private func frontmostChanged(_ app: NSRunningApplication?) {
        let isGame = app?.bundleIdentifier == Self.gameBundleId
        let isHUDClick = app?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            && (NSApp.keyWindow == nil || NSApp.keyWindow === panel)
        let isDesktopClick = app?.bundleIdentifier == "com.apple.finder" || app?.bundleIdentifier == "com.apple.dock"
        gameIsFrontmost = isGame || ((isHUDClick || isDesktopClick) && gameIsFrontmost)
        setOverviewHotKey(enabled: gameIsFrontmost)
        update()
    }

    private func update() {
        syncPreviewWindow()
        let visibleMode = model.hudMode == .scoreboard || !model.hudClosed
        let wanted = model.settings.showOverlay && model.live != nil && !model.isHUDPreview && visibleMode && gameIsFrontmost
        guard wanted else { panel?.orderOut(nil); return }
        let panel = self.panel ?? makePanel()
        fitToContent(panel)
        panel.orderFrontRegardless()
    }

    /// Sizes the panel to its content and places it at the saved anchor of the current mode (first time: HUD top right, overview top centre).
    private func fitToContent(_ panel: NSPanel) {
        guard let hosting else { return }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        let screen = (Self.gameScreen() ?? panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let modeChanged = fittedMode != model.hudMode
        let mode = model.hudMode
        let fallback = mode == .scoreboard
            ? NSPoint(x: screen.midX - size.width / 2, y: screen.maxY - 40)
            : NSPoint(x: screen.maxX - size.width - 20, y: screen.maxY - 60)
        var anchor = anchor(for: mode) ?? fallback
        if !screen.insetBy(dx: -1, dy: -1).contains(anchor) {
            anchor = fallback
            setAnchor(anchor, for: mode)
        }
        var origin = NSPoint(x: anchor.x, y: anchor.y - size.height)
        origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        origin.y = min(max(origin.y, screen.minY), screen.maxY - size.height)
        let frame = NSRect(origin: origin, size: size)
        fittedMode = model.hudMode
        if modeChanged {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.update() }
        }
        guard panel.frame != frame else { return }
        movingProgrammatically = true
        panel.setFrame(frame, display: true)
        movingProgrammatically = false
    }

    /// Screen showing the largest League game window (any layer, so fullscreen counts), from window bounds only.
    static func gameScreen() -> NSScreen? {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: gameBundleId).first?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]],
              let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        let bounds = windows
            .filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid }
            .compactMap { ($0[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) } }
            .max { $0.width * $0.height < $1.width * $1.height }
        guard let bounds else { return nil }
        let flipped = CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
        return NSScreen.screens.max { a, b in
            a.frame.intersection(flipped).width * a.frame.intersection(flipped).height
                < b.frame.intersection(flipped).width * b.frame.intersection(flipped).height
        }
    }

    private func makePanel() -> NSPanel {
        let screen = Self.gameScreen()?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panel = NSPanel(contentRect: NSRect(x: screen.maxX - 330, y: screen.maxY - 500, width: 310, height: 440),
                            styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.movingProgrammatically, let panel = self.panel else { return }
                self.setAnchor(NSPoint(x: panel.frame.minX, y: panel.frame.maxY), for: self.model.hudMode)
            }
        }
        let hosting = NSHostingView(rootView: AnyView(InGameStage().environment(model)))
        panel.contentView = hosting
        self.hosting = hosting
        self.panel = panel
        return panel
    }

    /// The preview runs in a normal window so it never floats over other apps.
    private func syncPreviewWindow() {
        if model.isHUDPreview {
            if previewWindow == nil {
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 900),
                                      styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
                window.title = tr("In-game HUD preview")
                window.titlebarAppearsTransparent = true
                window.appearance = NSAppearance(named: .darkAqua)
                window.isReleasedWhenClosed = false
                window.contentView = NSHostingView(rootView: HUDPreviewScene().environment(model))
                window.center()
                previewWindow = window
                NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.model.endHUDPreview()
                        self?.previewWindow = nil
                    }
                }
            }
            previewWindow?.makeKeyAndOrderFront(nil)
        } else if let window = previewWindow {
            previewWindow = nil
            window.close()
        }
    }

    // MARK: Hotkeys

    private func registerHotKeys() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            var hotKey = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            guard let context else { return noErr }
            let controller = Unmanaged<InGameHUDController>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { controller.hotKeyPressed(hotKey.id) }
            return noErr
        }, 1, &spec, context, nil)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_ANSI_H), UInt32(controlKey | shiftKey), EventHotKeyID(signature: OSType(0x5550_2121), id: 1),
                            GetApplicationEventTarget(), 0, &ref)
        hotKeys.append(ref)
    }

    /// Shift+Tab is only claimed while the game is in front so it keeps working everywhere else.
    private func setOverviewHotKey(enabled: Bool) {
        if enabled, overviewHotKey == nil {
            RegisterEventHotKey(UInt32(kVK_Tab), UInt32(shiftKey), EventHotKeyID(signature: OSType(0x5550_2121), id: 2),
                                GetApplicationEventTarget(), 0, &overviewHotKey)
        } else if !enabled, let ref = overviewHotKey {
            UnregisterEventHotKey(ref)
            overviewHotKey = nil
        }
    }

    private func hotKeyPressed(_ id: UInt32) {
        switch id {
        case 1: model.hudClosed.toggle()
        case 2:
            model.hudMode = model.hudMode == .hud ? .scoreboard : .hud
        default: break
        }
    }
}

// MARK: - HUD view

/// Whatever the overlay currently shows: the compact HUD with its alerts, or the match overview.
struct InGameStage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.hudMode == .scoreboard {
                InGameScoreboard()
            } else if !model.hudClosed {
                ScaledContent(scale: model.settings.hudScale) {
                    VStack(alignment: .trailing, spacing: 8) {
                        InGameHUDView()
                        if model.settings.hudToasts {
                            ForEach(model.hud.toasts) { ToastView(toast: $0) }
                        }
                    }
                    .animation(.snappy(duration: 0.25), value: model.hud.toasts)
                }
            }
        }
        .padding(6)
        .fixedSize()
        .environment(\.colorScheme, .dark)
    }
}

/// Header controls shared by both overlay modes.
struct OverlayControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 4) {
            control(model.hudMode == .hud ? "rectangle.expand.vertical" : "rectangle.compress.vertical",
                    model.hudMode == .hud ? tr("Match overview (⇧Tab)") : tr("Back to HUD (⇧Tab)")) {
                model.hudMode = model.hudMode == .hud ? .scoreboard : .hud
            }
            control("xmark", tr("Hide (⌃⇧H brings it back)")) {
                if model.hudMode == .scoreboard { model.hudMode = .hud } else { model.hudClosed = true }
            }
        }
    }

    private func control(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9.5, weight: .bold)).foregroundStyle(Theme.textSecondary)
                .frame(width: 20, height: 20)
                .background(Theme.raised, in: Circle())
                .overlay(Circle().strokeBorder(Theme.hairline))
                .contentShape(Circle())
        }
        .buttonStyle(.plain).handCursor()
        .help(help)
    }
}

/// Empty area behind the HUD content that drags the panel, so gestures on top (the resize grip, buttons) stay separate.
struct WindowDragHandle: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Lays out content at its natural size, then scales it so the hosting panel resizes with it.
struct ScaledContent<Content: View>: View {
    let scale: Double
    @ViewBuilder var content: Content
    @State private var size: CGSize = .zero

    var body: some View {
        content
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
    }
}

/// Corner handle that resizes the mini HUD by dragging; the scale is remembered.
private struct ResizeGrip: View {
    @Environment(AppModel.self) private var model
    @State private var start: Double?

    var body: some View {
        Image(systemName: "arrow.down.right")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(Theme.textMuted)
            .frame(width: 16, height: 16)
            .background(Theme.raised.opacity(0.9), in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .padding(3)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let base = start ?? model.settings.hudScale
                        start = base
                        let delta = (value.translation.width + value.translation.height) / 2 / 252
                        model.settings.hudScale = min(max(base + delta, 0.7), 1.8)
                    }
                    .onEnded { _ in start = nil }
            )
            .onHover { inside in
                if inside {
                    if #available(macOS 15, *) { NSCursor.frameResize(position: .bottomRight, directions: .all).push() } else { NSCursor.crosshair.push() }
                } else {
                    NSCursor.pop()
                }
            }
            .help(tr("Drag to resize"))
    }
}

/// Compact HUD: clock and score, objective timers, the enemy team with all items, and your next item.
struct InGameHUDView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let live = model.live {
            VStack(alignment: .leading, spacing: 8) {
                header(live)
                ObjectiveStrip(live: live)
                if !model.settings.hudCompact {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                    EnemyWatch()
                    MyGoal()
                }
            }
            .padding(10)
            .frame(width: 252)
            .background(WindowDragHandle())
            .background(Theme.background.opacity(0.88), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.accent.opacity(0.3)))
            .overlay(alignment: .bottomTrailing) { ResizeGrip() }
        }
    }

    private func header(_ live: LiveGameSnapshot) -> some View {
        HStack(spacing: 6) {
            Text(formatTime(live.gameTime)).font(.callout.weight(.bold).monospacedDigit()).foregroundStyle(Theme.text)
            HStack(spacing: 3) {
                Image(systemName: "figure.fencing").font(.system(size: 9, weight: .semibold))
                Text("\(live.ally.kills) – \(live.enemy.kills)").font(.caption.weight(.semibold).monospacedDigit())
            }
            .foregroundStyle(Theme.textSecondary)
            .help(tr("Kills"))
            let diff = live.goldDiff
            Text((diff >= 0 ? "+" : "") + compact(Double(diff)))
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(diff >= 0 ? Theme.win : Theme.loss)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background((diff >= 0 ? Theme.win : Theme.loss).opacity(0.15), in: Capsule())
                .help(tr("Item gold difference"))
            Spacer(minLength: 0)
            OverlayControls()
        }
    }
}

/// Dragon, Baron and inhibitor timers; inhibitors are coloured by side.
private struct ObjectiveStrip: View {
    let live: LiveGameSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(live.objectives) { objective in
                row(objective.symbol, objective.name, objective.respawnAt.map { $0 - live.gameTime }, tint: Theme.gold)
            }
            ForEach(live.inhibitors) { inhib in
                row("building.columns.fill", inhib.name, inhib.respawnAt - live.gameTime, tint: inhib.ours ? Theme.ally : Theme.enemy)
            }
        }
    }

    private func row(_ symbol: String, _ name: String, _ remaining: Double?, tint: Color) -> some View {
        let alive = (remaining ?? 0) <= 0
        return HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(alive ? Theme.good : tint).frame(width: 14)
            Text(name).font(.caption).foregroundStyle(tint == Theme.gold ? Theme.text : tint).lineLimit(1)
            Spacer(minLength: 4)
            Text(alive ? tr("Alive") : formatTime(remaining ?? 0))
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(alive ? Theme.good : (remaining ?? 0) <= 60 ? Theme.warning : Theme.text)
        }
    }
}

/// Enemy champions with level, respawn timer, K/D/A and every item they hold.
private struct EnemyWatch: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(model.hud.enemies) { enemy in
                HStack(spacing: 6) {
                    ChampionIcon(id: enemy.championId, size: 24, ring: Theme.enemy.opacity(0.55))
                        .overlay {
                            if enemy.isDead {
                                Text("\(Int(enemy.respawn))").font(.caption2.weight(.heavy).monospacedDigit()).foregroundStyle(.white)
                                    .shadow(color: .black, radius: 2)
                                    .frame(width: 24, height: 24).background(Theme.loss.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            Text("\(enemy.level)").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.text)
                                .padding(.horizontal, 2).background(Theme.background, in: RoundedRectangle(cornerRadius: 2)).offset(x: 3, y: 3)
                        }
                        .help(model.gameData.championName(enemy.championId))
                    Text("\(enemy.kills)/\(enemy.deaths)/\(enemy.assists)").font(.system(size: 9.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary).frame(width: 40, alignment: .leading)
                    HStack(spacing: 1.5) {
                        ForEach(Array(enemy.items.enumerated()), id: \.offset) { _, id in
                            ItemIcon(id: id, size: 18)
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(enemy.counterItems.contains(id) ? Theme.loss : .clear, lineWidth: 1.5))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// Next core item with the gold still missing, plus CS per minute.
private struct MyGoal: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            if let goal = model.hud.goal {
                ItemIcon(id: goal.itemId, size: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.remaining == 0 ? tr("Ready to buy") : tr("%d g left", goal.remaining))
                        .font(.system(size: 9.5, weight: .bold).monospacedDigit()).foregroundStyle(goal.remaining == 0 ? Theme.good : Theme.gold)
                    Meter(value: 1 - Double(goal.remaining) / Double(goal.total), tint: goal.remaining == 0 ? Theme.good : Theme.gold,
                          track: Theme.gold.opacity(0.15), height: 3)
                }
                .help(goal.name)
            }
            Spacer(minLength: 6)
            Text(tr("%@ CS/m", decimal(model.hud.csPerMinute))).font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(model.hud.csPerMinute >= 7 ? Theme.good : model.hud.csPerMinute >= 5.5 ? Theme.textSecondary : Theme.warning)
        }
    }
}

private struct ToastView: View {
    let toast: Toast

    var body: some View {
        let color: Color = switch toast.tone {
        case .good: Theme.good
        case .warning: Theme.warning
        case .danger: Theme.loss
        case .info: Theme.accentBright
        }
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: toast.symbol).font(.callout).foregroundStyle(color).frame(width: 18)
            Text(toast.text).font(.caption.weight(.medium)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 252)
        .background(Theme.background.opacity(0.9))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(color.opacity(0.35)))
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }
}

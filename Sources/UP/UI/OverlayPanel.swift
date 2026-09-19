import AppKit
import SwiftUI

/// Floating, always-on-top panel shown over the game window (works in windowed / borderless mode).
@MainActor
final class OverlayController {
    private var panel: NSPanel?
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = model.live != nil
            _ = model.settings.showOverlay
            _ = model.settings.overlayClickThrough
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.observe()
            }
        }
        update()
    }

    private func update() {
        let visible = model.settings.showOverlay && model.live != nil
        if visible {
            let panel = self.panel ?? makePanel()
            panel.ignoresMouseEvents = model.settings.overlayClickThrough
            panel.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 40, y: 400, width: 260, height: 220),
                            styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.setFrameAutosaveName("UPOverlay")
        panel.contentView = NSHostingView(rootView: OverlayView().environment(model))
        self.panel = panel
        return panel
    }
}

struct OverlayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let live = model.live {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "shield.lefthalf.filled").font(.caption2.bold()).foregroundStyle(Theme.accentBright)
                    Spacer()
                    Text(formatTime(live.gameTime)).font(.caption.monospacedDigit())
                }
                ForEach(live.objectives) { objective in
                    row(objective.symbol, objective.name, objective.respawnAt.map { $0 - live.gameTime })
                }
                ForEach(live.inhibitors, id: \.name) { inhib in
                    row("building.columns", inhib.name, inhib.respawnAt - live.gameTime)
                }
                Rectangle().fill(Theme.hairlineStrong).frame(height: 1)
                HStack {
                    Image(systemName: "dollarsign.circle")
                    Text(tr("Item gold"))
                    Spacer()
                    Text((live.goldDiff > 0 ? "+" : "") + live.goldDiff.formatted())
                        .foregroundStyle(live.goldDiff >= 0 ? Theme.win : Theme.loss).bold()
                }
                .font(.caption)
                HStack {
                    Image(systemName: "flame")
                    Text(tr("Dragons %d : %d", live.ally.dragons.count, live.enemy.dragons.count))
                    Spacer()
                    Text(tr("Towers %d : %d", live.ally.towers, live.enemy.towers))
                }
                .font(.caption)
                if let alert = live.alerts.last {
                    Text("⚠︎ \(alert.champion): \(alert.itemName)").font(.caption2).foregroundStyle(.orange).lineLimit(1)
                }
            }
            .padding(10)
            .foregroundStyle(Theme.text)
            .frame(width: 240)
            .background(Theme.background.opacity(0.82), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.accent.opacity(0.35)))
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ symbol: String, _ name: String, _ remaining: Double?) -> some View {
        HStack {
            Image(systemName: symbol).frame(width: 16)
            Text(name)
            Spacer()
            if let remaining, remaining > 0 {
                Text(formatTime(remaining)).monospacedDigit().bold()
            } else {
                Text(tr("Alive")).foregroundStyle(Theme.good).bold()
            }
        }
        .font(.caption)
    }
}

import SwiftUI

/// The icon the pointer rests on, shared with the layer that draws its tooltip.
@MainActor
@Observable
final class TooltipState {
    struct Content: Equatable {
        var id: String
        var title: String
        var subtitle: String?
        var text: String
        var point: CGPoint
    }

    var content: Content?

    func show(_ content: Content) { self.content = content }

    func hide(_ id: String) {
        if content?.id == id { content = nil }
    }
}

extension View {
    /// Shows the game's own description next to the pointer while it rests on this icon.
    func gameTooltip(id: String, title: String, subtitle: String? = nil, text: String) -> some View {
        modifier(GameTooltip(id: id, title: title, subtitle: subtitle, text: text))
    }
}

private struct GameTooltip: ViewModifier {
    @Environment(TooltipState.self) private var state: TooltipState?
    let id: String
    let title: String
    var subtitle: String?
    let text: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if title.isEmpty {
            content
        } else if let state {
            content.onContinuousHover(coordinateSpace: .global) { phase in
                switch phase {
                case let .active(point):
                    state.show(.init(id: id, title: title, subtitle: subtitle, text: text, point: point))
                case .ended:
                    state.hide(id)
                }
            }
        } else {
            content.help(text.isEmpty ? title : "\(title)\n\(text)")
        }
    }
}

/// Draws the hovered icon's tooltip over the whole window, so no panel can clip it.
struct TooltipLayer: View {
    @Environment(TooltipState.self) private var state

    var body: some View {
        GeometryReader { geo in
            if let content = state.content {
                let left = content.point.x < geo.size.width / 2
                let top = content.point.y < geo.size.height / 2
                card(content)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: Alignment(horizontal: left ? .leading : .trailing, vertical: top ? .top : .bottom))
                    .padding(.leading, left ? content.point.x + 18 : 0)
                    .padding(.trailing, left ? 0 : geo.size.width - content.point.x + 18)
                    .padding(.top, top ? content.point.y + 18 : 0)
                    .padding(.bottom, top ? 0 : geo.size.height - content.point.y + 18)
            }
        }
        .allowsHitTesting(false)
    }

    private func card(_ content: TooltipState.Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(content.title).font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                if let subtitle = content.subtitle {
                    Text(subtitle).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.gold)
                }
            }
            if !content.text.isEmpty {
                Text(content.text).font(.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(width: 320, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .panelBackground(Theme.sidebar, radius: 10)
        .shadow(color: .black.opacity(0.45), radius: 14, y: 4)
    }
}

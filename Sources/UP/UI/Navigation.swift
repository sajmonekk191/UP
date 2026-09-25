import SwiftUI

// MARK: - Top tabs

/// Text tabs next to the logo; the active one sits on an accent capsule.
struct TopTabs: View {
    @Binding var page: Page
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(Page.tabs.enumerated()), id: \.element) { index, tab in
                TopTab(page: tab, shortcut: index + 1, active: page.section == tab, highlight: highlight) {
                    withAnimation(.snappy(duration: 0.25)) { page = tab }
                }
            }
        }
    }
}

private struct TopTab: View {
    let page: Page
    let shortcut: Int
    let active: Bool
    let highlight: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(page.title)
                .font(.system(size: 13, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? Theme.text : hovering ? Theme.text.opacity(0.85) : Theme.textSecondary)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background {
                    if active {
                        Capsule().fill(LinearGradient(colors: [Theme.accent.opacity(0.55), Theme.accentDeep.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                            .shadow(color: Theme.accent.opacity(0.35), radius: 8)
                            .matchedGeometryEffect(id: "active", in: highlight)
                    } else if hovering {
                        Capsule().fill(Theme.hover)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain).handCursor()
        .onHover { hovering = $0 }
        .help("\(page.title)  ⌘\(shortcut)")
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// Capsule in the top bar that brings the champ select window back while a draft runs.
struct LiveDraftPill: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(tr("Champ select is live"), systemImage: "person.2.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(LinearGradient(colors: [Theme.accentBright, Theme.accent], startPoint: .top, endPoint: .bottom), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain).handCursor()
        .help(tr("Open the champ select window"))
    }
}

// MARK: - Side rail

/// Slim launcher-style rail on the left edge with the sections, the live draft shortcut and settings.
struct SideRail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Binding var page: Page
    var openChampSelect: () -> Void
    @Namespace private var highlight

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(Page.tabs.enumerated()), id: \.element) { index, tab in
                RailButton(page: tab, shortcut: index + 1, active: page.section == tab, highlight: highlight) {
                    withAnimation(.snappy(duration: 0.28)) { page = tab }
                }
            }
            Spacer(minLength: 12)
            if model.isInChampSelect {
                RailLiveButton(action: openChampSelect)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            Button { openSettings() } label: {
                Image(systemName: "gearshape.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textMuted)
                    .frame(width: 44, height: 40).contentShape(Rectangle())
            }
            .buttonStyle(.plain).handCursor()
            .help(tr("Settings"))
        }
        .animation(.snappy(duration: 0.3), value: model.isInChampSelect)
        .padding(.vertical, 14)
        .frame(width: 80)
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.hairline).frame(width: 1) }
    }
}

private struct RailButton: View {
    let page: Page
    let shortcut: Int
    let active: Bool
    let highlight: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: page.symbol).font(.system(size: 17, weight: .semibold)).frame(height: 20)
                Text(page.title).font(.system(size: 9.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
            }
            .foregroundStyle(active ? Color.white : hovering ? Theme.text : Theme.textSecondary)
            .frame(width: 66, height: 58)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.accent.opacity(0.9), Theme.accentDeep], startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.accentBright.opacity(0.4)))
                        .shadow(color: Theme.accent.opacity(0.45), radius: 10, y: 3)
                        .matchedGeometryEffect(id: "tile", in: highlight)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.hover)
                }
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                if active {
                    Capsule().fill(Theme.accentBright).frame(width: 3, height: 26)
                        .shadow(color: Theme.accentBright.opacity(0.8), radius: 6)
                        .matchedGeometryEffect(id: "marker", in: highlight)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).handCursor()
        .onHover { hovering = $0 }
        .help("\(page.title)  ⌘\(shortcut)")
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

private struct RailLiveButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Pulse(color: Theme.good.opacity(0.35), scale: 0.7...1.3).frame(width: 22, height: 22)
                    Image(systemName: "person.2.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                }
                .frame(height: 20)
                Text(tr("Draft")).font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 66, height: 58)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Theme.good.opacity(0.9), Theme.good.opacity(0.55)], startPoint: .top, endPoint: .bottom)))
            .shadow(color: Theme.good.opacity(0.45), radius: 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).handCursor()
        .help(tr("Open the champ select window"))
    }
}

// MARK: - League-style tabs

/// Uppercase section tabs with a glowing underline, in the spirit of the League client's top navigation.
struct LeagueTabs: View {
    @Binding var page: Page
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(Page.tabs.enumerated()), id: \.element) { index, tab in
                LeagueTab(page: tab, shortcut: index + 1, active: page.section == tab, highlight: highlight) {
                    withAnimation(.snappy(duration: 0.28)) { page = tab }
                }
            }
        }
        .frame(height: 52)
    }
}

private struct LeagueTab: View {
    let page: Page
    let shortcut: Int
    let active: Bool
    let highlight: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(page.title.uppercased())
                .font(.system(size: 12, weight: .heavy)).tracking(1.2)
                .foregroundStyle(active ? Color.white : hovering ? Theme.text : Theme.textSecondary)
                .shadow(color: active ? Theme.accentBright.opacity(0.6) : .clear, radius: 8)
                .padding(.horizontal, 14)
                .frame(maxHeight: .infinity)
                .background(alignment: .bottom) {
                    if active {
                        ZStack(alignment: .bottom) {
                            Ellipse().fill(Theme.accent.opacity(0.28)).frame(height: 30).blur(radius: 12).offset(y: 14)
                            Capsule().fill(LinearGradient(colors: [Theme.accentBright, Theme.accent], startPoint: .leading, endPoint: .trailing))
                                .frame(height: 3)
                                .shadow(color: Theme.accentBright.opacity(0.9), radius: 6)
                                .padding(.horizontal, 10)
                        }
                        .matchedGeometryEffect(id: "underline", in: highlight)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).handCursor()
        .onHover { hovering = $0 }
        .help("\(page.title)  ⌘\(shortcut)")
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// Angular call-to-action shaped like the League client's Play button, shown while a draft runs.
struct LeagueDraftButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle().fill(Theme.good).frame(width: 7, height: 7)
                    .overlay(Pulse(color: Theme.good.opacity(0.6), scale: 1...2.2, lineWidth: 2))
                Text(tr("Champ select").uppercased()).font(.system(size: 11.5, weight: .heavy)).tracking(1.1).foregroundStyle(.white)
            }
            .padding(.horizontal, 20).frame(height: 32)
            .background(ChamferedRectangle(inset: 9).fill(LinearGradient(colors: [Theme.accent, Theme.accentDeep], startPoint: .top, endPoint: .bottom)))
            .overlay(ChamferedRectangle(inset: 9).stroke(LinearGradient(colors: [Theme.gold, Theme.gold.opacity(0.5)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5))
            .shadow(color: Theme.accent.opacity(0.5), radius: 10)
            .contentShape(ChamferedRectangle(inset: 9))
        }
        .buttonStyle(.plain).handCursor()
        .help(tr("Open the champ select window"))
    }
}

/// Rectangle with cut corners on the left and right ends.
private struct ChamferedRectangle: Shape {
    var inset: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            p.closeSubpath()
        }
    }
}

// MARK: - Floating dock

/// Floating section switcher at the bottom of the main window, with a live champ select shortcut beside it.
struct NavigationDock: View {
    @Environment(AppModel.self) private var model
    @Binding var page: Page
    var openChampSelect: () -> Void
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(Array(Page.tabs.enumerated()), id: \.element) { index, tab in
                    DockButton(page: tab, shortcut: index + 1, active: page.section == tab, highlight: highlight) {
                        withAnimation(.snappy(duration: 0.28)) { page = tab }
                    }
                }
            }
            .padding(5)
            .background(GlassBackground(radius: 22))
            if model.isInChampSelect {
                LiveDraftButton(action: openChampSelect)
                    .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.3), value: model.isInChampSelect)
    }
}

private struct GlassBackground: View {
    let radius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape.fill(.ultraThinMaterial)
            .overlay(shape.fill(Theme.sidebar.opacity(0.82)))
            .overlay(shape.strokeBorder(LinearGradient(colors: [Theme.hairlineStrong, Theme.hairline], startPoint: .top, endPoint: .bottom)))
            .shadow(color: .black.opacity(0.55), radius: 24, y: 12)
    }
}

private struct DockButton: View {
    let page: Page
    let shortcut: Int
    let active: Bool
    let highlight: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: page.symbol).font(.system(size: 15, weight: .semibold)).frame(height: 18)
                Text(page.title).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(active ? Color.white : hovering ? Theme.text : Theme.textSecondary)
            .frame(width: 96, height: 50)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.accent, Theme.accentDeep], startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(Theme.accentBright.opacity(0.45)))
                        .shadow(color: Theme.accent.opacity(0.45), radius: 10, y: 3)
                        .matchedGeometryEffect(id: "active", in: highlight)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 17, style: .continuous).fill(Theme.hover)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain).handCursor()
        .onHover { hovering = $0 }
        .help("\(page.title)  ⌘\(shortcut)")
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// Pulsing button that brings the champ select window to the front while a draft runs.
private struct LiveDraftButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack {
                    Pulse(color: Theme.good.opacity(0.35), scale: 0.7...1.25).frame(width: 16, height: 16)
                    Circle().fill(Theme.good).frame(width: 8, height: 8)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(tr("Champ select")).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    Text(tr("Live · open the assistant")).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 60)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Theme.accentBright, Theme.accent], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.25)))
            .shadow(color: Theme.accent.opacity(0.5), radius: 18, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain).handCursor()
        .help(tr("Open the champ select window"))
    }
}

// MARK: - Compact side pill

/// Floating icon-only pill on the left; the section name slides out on hover.
struct SidePill: View {
    @Environment(AppModel.self) private var model
    @Binding var page: Page
    var openChampSelect: () -> Void
    @Namespace private var highlight

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(Page.tabs.enumerated()), id: \.element) { index, tab in
                PillButton(page: tab, shortcut: index + 1, active: page.section == tab, highlight: highlight) {
                    withAnimation(.snappy(duration: 0.28)) { page = tab }
                }
            }
            if model.isInChampSelect {
                Rectangle().fill(Theme.hairline).frame(width: 26, height: 1).padding(.vertical, 2)
                PillLiveButton(action: openChampSelect)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.3), value: model.isInChampSelect)
        .padding(6)
        .background(GlassBackground(radius: 26))
    }
}

private struct PillButton: View {
    let page: Page
    let shortcut: Int
    let active: Bool
    let highlight: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: page.symbol).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(active ? Color.white : hovering ? Theme.text : Theme.textSecondary)
                .frame(width: 44, height: 44)
                .background {
                    if active {
                        Circle().fill(LinearGradient(colors: [Theme.accent, Theme.accentDeep], startPoint: .top, endPoint: .bottom))
                            .overlay(Circle().strokeBorder(Theme.accentBright.opacity(0.45)))
                            .shadow(color: Theme.accent.opacity(0.5), radius: 10)
                            .matchedGeometryEffect(id: "active", in: highlight)
                    } else if hovering {
                        Circle().fill(Theme.hover)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain).handCursor()
        .onHover { hovering = $0 }
        .overlay(alignment: .leading) {
            if hovering {
                Text("\(page.title)  ⌘\(shortcut)").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.text)
                    .fixedSize()
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.raised, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.hairlineStrong))
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                    .offset(x: 56)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.snappy(duration: 0.18), value: hovering)
        .accessibilityLabel(page.title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

private struct PillLiveButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "person.2.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.good))
                .overlay(Pulse(color: Theme.good.opacity(0.6), scale: 1...1.35, lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain).handCursor()
        .help(tr("Open the champ select window"))
    }
}

// MARK: - Notices

/// Short-lived messages about actions and connection problems, stacked at the bottom of the window.
struct NoticeStack: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            ForEach(model.notices) { notice in
                NoticeView(notice: notice)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.3), value: model.notices)
    }
}

private struct NoticeView: View {
    let notice: Notice

    var body: some View {
        let (symbol, color): (String, Color) = switch notice.kind {
        case .success: ("checkmark.circle.fill", Theme.good)
        case .warning: ("exclamationmark.triangle.fill", Theme.warning)
        case .info: ("info.circle.fill", Theme.accentBright)
        }
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.callout).foregroundStyle(color)
            Text(notice.text).font(.callout.weight(.medium)).foregroundStyle(Theme.text).lineLimit(2)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: 520)
        .background(Theme.raised, in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.35)))
        .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
    }
}

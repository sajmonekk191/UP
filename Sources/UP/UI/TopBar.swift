import SwiftUI

/// Top navigation: brand, section tabs, the search bar and account controls.
struct TopBar: View {
    @Environment(AppModel.self) private var model
    @Environment(Localizer.self) private var localizer
    @Binding var page: Page
    var openChampSelect: () -> Void
    var onSuggestion: (SearchSuggestion) -> Void

    var body: some View {
        HStack(spacing: 18) {
            AppMark(size: 30)
                .padding(.leading, 86)
                .background(WindowChrome())

            HStack(spacing: 2) {
                ForEach(Page.tabs) { tab in
                    TabButton(page: tab, active: page == tab) { withAnimation(.snappy(duration: 0.2)) { page = tab } }
                }
            }
            .padding(3)
            .background(Theme.surface.opacity(0.7), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.hairline))

            Spacer(minLength: 12)

            if model.isInChampSelect {
                Button(action: openChampSelect) {
                    Label(tr("Champ select is live"), systemImage: "person.2.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(LinearGradient(colors: [Theme.accentBright, Theme.accent], startPoint: .top, endPoint: .bottom), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            SearchBar(onSelect: onSuggestion)

            Menu {
                ForEach(AppLanguage.allCases) { language in
                    Button { localizer.language = language } label: { Text("\(language.flag)  \(language.nativeName)") }
                }
            } label: {
                Text(localizer.language.flag).font(.system(size: 15))
                    .frame(width: 30, height: 30)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.hairline))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .help(tr("Language"))

            ProfileButton()
        }
        .padding(.trailing, 18)
        .frame(height: 52)
        .background(Theme.sidebar)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

private struct TabButton: View {
    let page: Page
    let active: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: page.symbol).font(.system(size: 11, weight: .semibold))
                Text(page.title).font(.system(size: 12.5, weight: active ? .semibold : .medium))
            }
            .foregroundStyle(active ? Theme.text : hovering ? Theme.text.opacity(0.85) : Theme.textSecondary)
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background {
                if active {
                    Capsule().fill(LinearGradient(colors: [Theme.accent.opacity(0.55), Theme.accentDeep.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                        .overlay(Capsule().strokeBorder(Theme.accentBright.opacity(0.35)))
                        .shadow(color: Theme.accent.opacity(0.35), radius: 8)
                } else if hovering {
                    Capsule().fill(Theme.hover)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct ProfileButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Menu {
            Text(model.me?.riotId ?? tr("Not connected"))
            Text(model.connection == .connected ? model.phaseTitle : tr("Looking for client…"))
            Divider()
            Button(tr("Settings")) { openSettings() }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                LCUImage(path: model.me?.profileIconId.map { "/lol-game-data/assets/v1/profile-icons/\($0).jpg" }, size: 30, corner: 15)
                    .overlay(Circle().strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1.5))
                Circle().fill(model.connection == .connected ? Theme.good : Theme.warning)
                    .frame(width: 9, height: 9).overlay(Circle().strokeBorder(Theme.sidebar, lineWidth: 2))
            }
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .help(model.connection == .connected ? "\(model.me?.riotId ?? "") · \(model.phaseTitle)" : tr("Looking for client…"))
    }
}

/// Gives the hosting window a unified toolbar so the traffic lights sit centred in the 52 pt top bar.
private struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window, window.toolbar == nil else { return }
            window.toolbar = NSToolbar(identifier: "UPMain")
            window.toolbarStyle = .unified
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Compact search field that widens on focus and suggests champions, players and #tags as you type.
struct SearchBar: View {
    @Environment(AppModel.self) private var model
    var onSelect: (SearchSuggestion) -> Void
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    private var suggestions: [SearchSuggestion] { SearchEngine.suggestions(for: query, model: model) }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(focused ? Theme.accentBright : Theme.textMuted)
            TextField(focused ? tr("Search champions, players, #tags") : tr("Search"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text)
                .focused($focused)
                .onSubmit { choose(highlighted) }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.escape) { query = ""; focused = false; return .handled }
                .onChange(of: query) { highlighted = 0 }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textMuted) }
                    .buttonStyle(.plain)
            } else if !focused {
                Text("⌘K").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.hairlineStrong))
            }
        }
        .padding(.horizontal, 11).frame(height: 32)
        .frame(width: focused ? 340 : 230)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(focused ? Theme.accent.opacity(0.7) : Theme.hairline))
        .animation(.snappy(duration: 0.2), value: focused)
        .overlay(alignment: .topTrailing) {
            if focused {
                SuggestionList(suggestions: suggestions, highlighted: highlighted, query: query) { choose($0) }
                    .offset(y: 40)
            }
        }
        .background {
            Button("") { focused = true }.keyboardShortcut("k", modifiers: .command).opacity(0)
        }
    }

    private func move(_ delta: Int) {
        let count = suggestions.count
        guard count > 0 else { return }
        highlighted = (highlighted + delta + count) % count
    }

    private func choose(_ index: Int) {
        let list = suggestions
        guard list.indices.contains(index) else { return }
        onSelect(list[index])
        query = ""
        focused = false
    }
}

private struct SuggestionList: View {
    @Environment(AppModel.self) private var model
    let suggestions: [SearchSuggestion]
    let highlighted: Int
    let query: String
    let onChoose: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if suggestions.isEmpty {
                Text(tr("No matches. Try a champion, a Riot ID like Name#TAG, or #mid.")).font(.caption).foregroundStyle(Theme.textMuted).padding(12)
            }
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, item in
                if index == 0 || suggestions[index - 1].section != item.section {
                    Text(item.section).eyebrow().padding(.horizontal, 10).padding(.top, index == 0 ? 4 : 10).padding(.bottom, 2)
                }
                Button { onChoose(index) } label: { row(item, active: index == highlighted) }
                    .buttonStyle(.plain)
            }
            Text(tr("↑↓ to move · ↩ to open · esc to close")).font(.system(size: 10)).foregroundStyle(Theme.textMuted)
                .frame(maxWidth: .infinity, alignment: .center).padding(.top, 6)
        }
        .padding(8)
        .frame(width: 340)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairlineStrong))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
    }

    private func row(_ item: SearchSuggestion, active: Bool) -> some View {
        HStack(spacing: 10) {
            Group {
                if let championId = item.championId {
                    ChampionIcon(id: championId, size: 28)
                } else if let icon = item.iconId {
                    LCUImage(path: "/lol-game-data/assets/v1/profile-icons/\(icon).jpg", size: 28, corner: 14)
                } else {
                    Image(systemName: item.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accentBright)
                        .frame(width: 28, height: 28).background(Theme.accentDeep.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                highlightedTitle(item.title).font(.callout).lineLimit(1)
                if !item.subtitle.isEmpty { Text(item.subtitle).font(.caption2).foregroundStyle(Theme.textMuted).lineLimit(1) }
            }
            Spacer()
            if active { Image(systemName: "return").font(.caption2).foregroundStyle(Theme.textMuted) }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(active ? Theme.accent.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    /// Title with the typed part in bold white and the rest dimmed.
    private func highlightedTitle(_ title: String) -> Text {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty, let range = title.lowercased().range(of: needle) else { return Text(title).foregroundColor(Theme.text) }
        let lower = title.distance(from: title.startIndex, to: range.lowerBound)
        let start = title.index(title.startIndex, offsetBy: lower)
        let end = title.index(start, offsetBy: title.distance(from: range.lowerBound, to: range.upperBound))
        return Text(title[..<start]).foregroundColor(Theme.textSecondary)
            + Text(title[start..<end]).foregroundColor(Theme.text).bold()
            + Text(title[end...]).foregroundColor(Theme.textSecondary)
    }
}

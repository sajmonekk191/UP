import SwiftUI

/// Window header: brand, the search bar and account controls, plus the section tabs in the League-style layout.
struct TopBar: View {
    @Environment(AppModel.self) private var model
    @Environment(Localizer.self) private var localizer
    let style: NavigationStyle
    @Binding var page: Page
    var openChampSelect: () -> Void
    var onSuggestion: (SearchSuggestion) -> Void

    var body: some View {
        ZStack {
            HStack(spacing: 12) {
                AppMark(size: 30)
                    .padding(.leading, 86)
                    .background(WindowChrome())
                if style == .top { TopTabs(page: $page).padding(.leading, 6) }
                if style == .league { LeagueTabs(page: $page).padding(.leading, 6) }
                Spacer(minLength: 12)
                if style.tabsInHeader {
                    if model.isInChampSelect {
                        Group {
                            if style == .top { LiveDraftPill(action: openChampSelect) } else { LeagueDraftButton(action: openChampSelect) }
                        }
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                    SearchBar(onSelect: onSuggestion)
                }
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
                .menuStyle(.button).buttonStyle(.plain).handCursor().menuIndicator(.hidden)
                .help(tr("Language"))
                ProfileButton()
            }
            if !style.tabsInHeader { SearchBar(onSelect: onSuggestion) }
        }
        .animation(.snappy(duration: 0.3), value: model.isInChampSelect)
        .padding(.trailing, 18)
        .frame(height: 52)
        .background(Theme.sidebar)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
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
            Picker(tr("Navigation style"), selection: Bindable(model.settings).navigationStyle) {
                ForEach(NavigationStyle.allCases) { Text($0.title).tag($0) }
            }
            Button(tr("Settings")) { openSettings() }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                LCUImage(path: model.me?.profileIconId.map { "/lol-game-data/assets/v1/profile-icons/\($0).jpg" }, size: 30, corner: 15)
                    .overlay(Circle().strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1.5))
                Circle().fill(model.connection == .connected ? Theme.good : Theme.warning)
                    .frame(width: 9, height: 9).overlay(Circle().strokeBorder(Theme.sidebar, lineWidth: 2))
            }
        }
        .menuStyle(.button).buttonStyle(.plain).handCursor().menuIndicator(.hidden)
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
            window.makeFirstResponder(nil)
            let observer = ObserverBox()
            observer.token = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in
                DispatchQueue.main.async { window.makeFirstResponder(nil) }
                observer.token.map(NotificationCenter.default.removeObserver)
                observer.token = nil
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ObserverBox: @unchecked Sendable {
        var token: NSObjectProtocol?
    }
}

/// Search field with a server picker; suggests champions, known players, accounts on the server and #tags as you type.
struct SearchBar: View {
    @Environment(AppModel.self) private var model
    var onSelect: (SearchSuggestion) -> Void
    @State private var query = ""
    @State private var highlighted = 0
    @State private var accounts = AccountResults()
    @FocusState private var focused: Bool

    private struct AccountResults {
        var key = ""
        var region: Region = .euw
        var hits: [AccountHit] = []
        var page = 0
        var done = false
        var loading = false
    }

    private var accountKey: String { "\(model.searchRegion.rawValue)|\(SearchEngine.accountName(query) ?? "")" }

    private var sections: (leading: [SearchSuggestion], accounts: [SearchSuggestion], tags: [SearchSuggestion]) {
        let local = SearchEngine.suggestions(for: query, model: model)
        let shown = Set(local.leading.map { $0.title.lowercased() })
        let remote = accounts.key == accountKey
            ? accounts.hits.map { SearchSuggestion(account: $0, region: accounts.region) }.filter { !shown.contains($0.title.lowercased()) }
            : []
        return (local.leading, remote, local.tags)
    }

    private var suggestions: [SearchSuggestion] {
        let sections = self.sections
        return sections.leading + sections.accounts + sections.tags
    }

    var body: some View {
        HStack(spacing: 7) {
            RegionPicker()
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(focused ? Theme.accentBright : Theme.textMuted)
            TextField(focused ? tr("Champion, player name or #tag") : tr("Search"), text: $query)
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
                    .buttonStyle(.plain).handCursor()
            } else if !focused {
                Text("⌘K").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.hairlineStrong))
            }
        }
        .padding(.leading, 5).padding(.trailing, 12).frame(height: 32)
        .frame(width: focused ? 480 : 340)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(focused ? Theme.accent.opacity(0.7) : Theme.hairline))
        .animation(.snappy(duration: 0.2), value: focused)
        .overlay(alignment: .top) {
            if focused {
                let sections = self.sections
                SuggestionList(leading: sections.leading, accounts: sections.accounts, tags: sections.tags,
                               region: model.searchRegion, accountName: SearchEngine.accountName(query),
                               searching: accounts.loading || accounts.key != accountKey, exhausted: accounts.done,
                               highlighted: highlighted, query: query, onChoose: choose, onReachEnd: loadMore)
                    .offset(y: 40)
            }
        }
        .background {
            Button("") { focused = true }.keyboardShortcut("k", modifiers: .command).opacity(0)
        }
        .task(id: accountKey) {
            let key = accountKey
            accounts = AccountResults(key: key, region: model.searchRegion)
            guard let name = SearchEngine.accountName(query) else { accounts.done = true; return }
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            await loadAccounts(name, key: key)
        }
    }

    private func loadMore() {
        guard let name = SearchEngine.accountName(query), accounts.key == accountKey, !accounts.loading, !accounts.done else { return }
        let key = accountKey
        Task { await loadAccounts(name, key: key) }
    }

    private func loadAccounts(_ name: String, key: String) async {
        accounts.loading = true
        let page = accounts.page + 1
        let hits = (try? await OpggAccounts.search(name, region: accounts.region, page: page)) ?? []
        guard accounts.key == key else { return }
        let seen = Set(accounts.hits.map(\.puuid))
        accounts.hits += hits.filter { !seen.contains($0.puuid) }
        accounts.page = page
        accounts.done = hits.count < 10 || name.contains("#")
        accounts.loading = false
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

/// Server the search looks up accounts on.
private struct RegionPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Section(tr("Search accounts on")) {
                ForEach(Region.allCases) { region in
                    Button { model.settings.searchRegion = region } label: {
                        if region == model.searchRegion {
                            Label("\(region.code) · \(region.title)", systemImage: "checkmark")
                        } else {
                            Text("\(region.code) · \(region.title)")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(model.searchRegion.code).font(.system(size: 10.5, weight: .bold))
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(Theme.accentBright)
            .padding(.horizontal, 8).frame(height: 22)
            .background(Theme.accentDeep.opacity(0.4), in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.button).buttonStyle(.plain).handCursor().menuIndicator(.hidden).fixedSize()
        .help(tr("Server to search accounts on"))
    }
}

private struct SuggestionList: View {
    let leading: [SearchSuggestion]
    let accounts: [SearchSuggestion]
    let tags: [SearchSuggestion]
    let region: Region
    let accountName: String?
    let searching: Bool
    let exhausted: Bool
    let highlighted: Int
    let query: String
    let onChoose: (Int) -> Void
    let onReachEnd: () -> Void
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        rows(leading, offset: 0)
                        if accountName != nil {
                            HStack(spacing: 6) {
                                Text(tr("Accounts on %@", region.code)).eyebrow()
                                if searching { Spinner(size: 10, lineWidth: 1.5) }
                            }
                            .padding(.horizontal, 10).padding(.top, leading.isEmpty ? 4 : 10).padding(.bottom, 2)
                            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, item in
                                row(item, index: leading.count + index)
                                    .onAppear { if index == accounts.count - 1 { onReachEnd() } }
                            }
                            status
                        }
                        rows(tags, offset: leading.count + accounts.count)
                        if leading.isEmpty, accounts.isEmpty, tags.isEmpty, accountName == nil {
                            Text(tr("No matches. Try a champion, a Riot ID like Name#TAG, or #mid.")).font(.caption).foregroundStyle(Theme.textMuted).padding(12)
                        }
                    }
                    .padding(8)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                .frame(height: min(max(contentHeight, 44), 440))
                .onChange(of: highlighted) { _, index in withAnimation(.snappy(duration: 0.15)) { proxy.scrollTo(index) } }
            }
            Text(tr("↑↓ to move · ↩ to open · esc to close")).font(.system(size: 10)).foregroundStyle(Theme.textMuted)
                .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 7)
                .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        }
        .frame(width: 480)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairlineStrong))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
    }

    @ViewBuilder
    private var status: some View {
        if searching {
            VStack(spacing: 2) {
                ForEach(0..<(accounts.isEmpty ? 3 : 2), id: \.self) { index in
                    HStack(spacing: 10) {
                        Bone(width: 28, height: 28, radius: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            Bone(width: [118, 96, 134][index], height: 10, line: 16)
                            Bone(width: [72, 88, 64][index], height: 7, line: 12)
                        }
                        Spacer(minLength: 6)
                        Bone(width: 20, height: 20, radius: 10)
                        Bone(width: 58, height: 8)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                }
            }
            .shimmering()
        } else if accounts.isEmpty, exhausted, let accountName {
            Text(tr("No account named “%@” on %@.", accountName, region.code)).font(.caption).foregroundStyle(Theme.textMuted)
                .padding(.horizontal, 10).padding(.vertical, 6)
        }
    }

    private func rows(_ items: [SearchSuggestion], offset: Int) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            if index == 0 || items[index - 1].section != item.section {
                Text(item.section).eyebrow().padding(.horizontal, 10).padding(.top, offset + index == 0 ? 4 : 10).padding(.bottom, 2)
            }
            row(item, index: offset + index)
        }
    }

    private func row(_ item: SearchSuggestion, index: Int) -> some View {
        let active = index == highlighted
        return Button { onChoose(index) } label: {
            HStack(spacing: 10) {
                Group {
                    if let championId = item.championId {
                        ChampionIcon(id: championId, size: 28)
                    } else if let url = item.imageURL {
                        LCUImage(path: url, size: 28, corner: 14)
                    } else if let icon = item.iconId {
                        LCUImage(path: "/lol-game-data/assets/v1/profile-icons/\(icon).jpg", size: 28, corner: 14)
                    } else {
                        Image(systemName: item.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accentBright)
                            .frame(width: 28, height: 28).background(Theme.accentDeep.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        highlightedTitle(item.title).font(.callout).lineLimit(1)
                        if let pro = item.pro { Chip(text: pro, tone: .gold, symbol: "trophy.fill").fixedSize() }
                    }
                    if !item.subtitle.isEmpty { Text(item.subtitle).font(.caption2).foregroundStyle(Theme.textMuted).lineLimit(1) }
                }
                Spacer(minLength: 6)
                if let rank = item.rank {
                    HStack(spacing: 4) {
                        RankEmblem(tier: item.tier, size: 20)
                        Text(rank).font(.caption2.weight(.semibold)).foregroundStyle(item.tier == nil ? Theme.textMuted : Theme.textSecondary).lineLimit(1)
                    }
                    .fixedSize()
                }
                if active { Image(systemName: "return").font(.caption2).foregroundStyle(Theme.textMuted) }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(active ? Theme.accent.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).handCursor()
        .id(index)
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

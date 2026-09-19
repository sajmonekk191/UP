import AppKit
import SwiftUI

@main
struct UPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @State private var hud: InGameHUDController?
    @State private var champSelect: ChampSelectWindowController?
    private let localizer = Localizer.shared

    var body: some Scene {
        Window("UP!", id: "main") {
            ContentView(openChampSelect: { champSelect?.show() })
                .environment(model)
                .environment(localizer)
                .id(localizer.language)
                .frame(minWidth: 1300, minHeight: 780)
                .onAppear {
                    guard hud == nil else { return }
                    model.start()
                    hud = InGameHUDController(model: model)
                    champSelect = ChampSelectWindowController(model: model)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandMenu(tr("Language")) {
                ForEach(AppLanguage.allCases) { language in
                    Button("\(language.flag)  \(language.nativeName)") { localizer.language = language }
                }
            }
            CommandMenu("UP!") {
                Button(tr("Open champ select window")) { champSelect?.show() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button(tr("Preview champ select")) { model.startPreview(); champSelect?.show() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button(tr("Preview in-game HUD")) { model.startHUDPreview() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Divider()
                Picker(tr("Navigation style"), selection: Bindable(model.settings).navigationStyle) {
                    ForEach(NavigationStyle.allCases) { Text($0.title).tag($0) }
                }
                Button(tr("Next navigation style")) { model.settings.navigationStyle = model.settings.navigationStyle.next }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button(tr("Accept match")) {
                    Task { await model.perform(tr("Match accepted")) { try await $0.post("/lol-matchmaking/v1/ready-check/accept") } }
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView().environment(model).environment(localizer).id(localizer.language).preferredColorScheme(.dark)
        }

        MenuBarExtra {
            MenuBarContent()
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--selftest") {
            NSApp.setActivationPolicy(.prohibited)
            Task { @MainActor in exit(await SelfTest.run()) }
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

enum Page: String, CaseIterable, Identifiable {
    case dashboard, builds, tierList, tools, history, player

    var id: String { rawValue }

    static let tabs: [Page] = [.dashboard, .builds, .tierList, .tools]

    /// Dock section the page belongs to; the full match history lives under the overview.
    var section: Page { self == .history ? .dashboard : self }

    var title: String {
        switch self {
        case .dashboard: tr("Overview")
        case .builds: tr("Builds & runes")
        case .tierList: tr("Tier list")
        case .history: tr("Match history")
        case .tools: tr("Tools")
        case .player: tr("Player")
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2.fill"
        case .builds: "books.vertical.fill"
        case .tierList: "chart.bar.fill"
        case .history: "clock.arrow.circlepath"
        case .tools: "wrench.and.screwdriver.fill"
        case .player: "person.crop.circle"
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    var openChampSelect: () -> Void
    @State private var page: Page = .dashboard
    @State private var returnPage: Page = .dashboard
    @State private var buildChampion: Int?
    @State private var championClass: String?
    @State private var tierLane: Lane = .middle
    @State private var playerQuery: PlayerQuery?
    @State private var visited: [Page] = [.dashboard]
    @State private var tooltip = TooltipState()

    var body: some View {
        let style = model.settings.navigationStyle
        VStack(spacing: 0) {
            TopBar(style: style, page: $page, openChampSelect: openChampSelect, onSuggestion: open)
                .zIndex(1)
            HStack(spacing: 0) {
                if style == .rail { SideRail(page: $page, openChampSelect: openChampSelect) }
                ZStack(alignment: .bottom) {
                    Theme.background
                    Theme.backdrop.frame(height: 360).frame(maxHeight: .infinity, alignment: .top)
                    ForEach(visited.contains(page) ? visited : visited + [page]) { shown in
                        PageHost(active: shown == page) { pageView(shown) }
                            .padding(.leading, style == .pill ? 76 : 0)
                    }
                    if style == .pill {
                        SidePill(page: $page, openChampSelect: openChampSelect)
                            .padding(.leading, 16)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                    VStack(spacing: 12) {
                        NoticeStack()
                        if style == .dock { NavigationDock(page: $page, openChampSelect: openChampSelect) }
                    }
                    .padding(.bottom, 18)
                }
            }
        }
        .overlay { TooltipLayer() }
        .environment(tooltip)
        .environment(\.openPlayer) { query in
            playerQuery = query
            go(.player)
        }
        .environment(\.contentBottomInset, style == .dock ? Theme.dockClearance : 40)
        .onChange(of: page) { _, shown in
            if !visited.contains(shown) { visited.append(shown) }
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        .task(id: model.isGrading) {
            guard !model.isGrading, model.myProfile != nil else { return }
            for prewarmed in [Page.history, .builds] where !visited.contains(prewarmed) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                if !visited.contains(prewarmed) { visited.append(prewarmed) }
            }
        }
        .animation(.snappy(duration: 0.3), value: style)
        .background { sectionShortcuts }
        .background { backShortcut }
        .background(Theme.background)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    @ViewBuilder
    private func pageView(_ shown: Page) -> some View {
        let back = BackLink(title: returnPage.title) { go(returnPage) }
        switch shown {
        case .dashboard: DashboardView { go(.history) }.equatable()
        case .builds: BuildsView(selection: $buildChampion, championClass: $championClass)
        case .tierList: TierListView(lane: $tierLane) { id in buildChampion = id; go(.builds) }.equatable()
        case .tools: ToolsView(openChampSelect: openChampSelect).equatable()
        case .history: HistoryView(back: back).equatable()
        case .player: PlayerView(query: $playerQuery, back: back).equatable()
        }
    }

    /// ⌘1–⌘4 switch between the dock sections.
    private var sectionShortcuts: some View {
        ForEach(Array(Page.tabs.enumerated()), id: \.element) { index, tab in
            Button("") { go(tab) }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                .opacity(0)
        }
    }

    /// ⌘[ leaves a sub-page; one shortcut for the window, since hidden pages stay built.
    @ViewBuilder
    private var backShortcut: some View {
        if !Page.tabs.contains(page) {
            Button("") { go(returnPage) }.keyboardShortcut("[", modifiers: .command).opacity(0)
        }
    }

    private func go(_ target: Page) {
        withAnimation(.snappy(duration: 0.28)) {
            if Page.tabs.contains(page), !Page.tabs.contains(target) { returnPage = page }
            page = target
        }
    }

    /// Navigates to whatever a search suggestion points at.
    private func open(_ suggestion: SearchSuggestion) {
        switch suggestion.kind {
        case let .champion(id):
            championClass = nil
            buildChampion = id
            go(.builds)
        case let .player(query), let .account(query):
            playerQuery = query
            go(.player)
        case let .tag(tag):
            if let lane = tag.lane {
                tierLane = lane
                go(.tierList)
            } else if let championClass = tag.championClass {
                self.championClass = championClass
                buildChampion = nil
                go(.builds)
            } else {
                switch tag {
                case .tierlist: go(.tierList)
                case .builds: go(.builds)
                case .history: go(.history)
                case .tools: go(.tools)
                case .overview: go(.dashboard)
                case .me: playerQuery = model.myQuery; go(.player)
                case .settings: openSettings()
                case .preview: model.startPreview(); openChampSelect()
                case .hud: model.startHUDPreview()
                default: break
                }
            }
        }
    }
}

/// Keeps a visited page built behind the window background while another one is shown, frozen at its last size so window resizes skip it.
private struct PageHost<Content: View>: View {
    let active: Bool
    @ViewBuilder var content: Content
    @State private var size: CGSize?

    var body: some View {
        Color.clear
            .overlay(alignment: .topLeading) {
                content.frame(width: active ? nil : size?.width, height: active ? nil : size?.height)
            }
            .clipped()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { if active { size = $0 } }
            .allowsHitTesting(active)
            .accessibilityHidden(!active)
            .zIndex(active ? 0 : -1)
            .transition(.identity)
    }
}

struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(tr("Open UP!")) {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button(tr("Quit UP!")) { NSApp.terminate(nil) }
    }
}

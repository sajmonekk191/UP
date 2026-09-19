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
    case dashboard, builds, tierList, history, tools, player

    var id: String { rawValue }

    static let tabs: [Page] = [.dashboard, .builds, .tierList, .history, .tools]

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
    @State private var buildChampion: Int?
    @State private var championClass: String?
    @State private var tierLane: Lane = .middle
    @State private var playerRiotId: String?

    var body: some View {
        VStack(spacing: 0) {
            TopBar(page: $page, openChampSelect: openChampSelect, onSuggestion: open)
                .zIndex(1)
            ZStack {
                Theme.background
                Theme.backdrop.frame(height: 360).frame(maxHeight: .infinity, alignment: .top)
                detail.transition(.opacity)
            }
        }
        .background(Theme.background)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    @ViewBuilder
    private var detail: some View {
        switch page {
        case .dashboard: DashboardView { withAnimation(.snappy(duration: 0.2)) { page = .history } }
        case .builds: BuildsView(selection: $buildChampion, championClass: $championClass)
        case .tierList: TierListView(lane: $tierLane) { id in buildChampion = id; page = .builds }
        case .history: HistoryView()
        case .tools: ToolsView(openChampSelect: openChampSelect)
        case .player: PlayerView(riotId: $playerRiotId)
        }
    }

    /// Navigates to whatever a search suggestion points at.
    private func open(_ suggestion: SearchSuggestion) {
        withAnimation(.snappy(duration: 0.2)) {
            switch suggestion.kind {
            case let .champion(id):
                championClass = nil
                buildChampion = id
                page = .builds
            case let .player(riotId):
                playerRiotId = riotId
                page = .player
            case let .tag(tag):
                if let lane = tag.lane {
                    tierLane = lane
                    page = .tierList
                } else if let championClass = tag.championClass {
                    self.championClass = championClass
                    page = .builds
                } else {
                    switch tag {
                    case .tierlist: page = .tierList
                    case .builds: page = .builds
                    case .history: page = .history
                    case .tools: page = .tools
                    case .overview: page = .dashboard
                    case .me: playerRiotId = model.me?.riotId; page = .player
                    case .settings: openSettings()
                    case .preview: model.startPreview(); openChampSelect()
                    case .hud: model.startHUDPreview()
                    default: break
                    }
                }
            }
        }
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

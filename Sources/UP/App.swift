import AppKit
import SwiftUI

@main
struct UPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @State private var overlay: OverlayController?
    @State private var champSelect: ChampSelectWindowController?
    private let localizer = Localizer.shared

    var body: some Scene {
        WindowGroup("UP!", id: "main") {
            ContentView(openChampSelect: { champSelect?.show() })
                .environment(model)
                .environment(localizer)
                .id(localizer.language)
                .frame(minWidth: 1300, minHeight: 780)
                .onAppear {
                    guard overlay == nil else { return }
                    model.start()
                    overlay = OverlayController(model: model)
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
            MenuBarContent(openChampSelect: { champSelect?.show() }).environment(model)
        } label: {
            Image(systemName: model.phase == "ReadyCheck" ? "bell.badge.fill" : "arrow.up.forward.circle.fill")
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
    case dashboard, builds, tierList, history, lookup, tools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: tr("Overview")
        case .builds: tr("Builds & runes")
        case .tierList: tr("Tier list")
        case .history: tr("Match history")
        case .lookup: tr("Player lookup")
        case .tools: tr("Tools")
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2.fill"
        case .builds: "books.vertical.fill"
        case .tierList: "chart.bar.fill"
        case .history: "clock.arrow.circlepath"
        case .lookup: "magnifyingglass"
        case .tools: "wrench.and.screwdriver.fill"
        }
    }

    static var groups: [(String, [Page])] {
        [
            (tr("Home"), [.dashboard]),
            (tr("Stats"), [.builds, .tierList]),
            (tr("Players"), [.history, .lookup]),
            (tr("Client"), [.tools]),
        ]
    }
}

/// Brand mark: gradient tile with the UP! wordmark.
struct AppMark: View {
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [Theme.accentBright, Theme.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("UP!").font(.system(size: size * 0.38, weight: .black)).foregroundStyle(.white).tracking(-0.5)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.accent.opacity(0.5), radius: size * 0.3)
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    var openChampSelect: () -> Void
    @State private var page: Page = .dashboard
    @State private var buildChampion: Int?

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(page: $page, openChampSelect: openChampSelect)
            Rectangle().fill(Theme.hairline).frame(width: 1)
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
        case .dashboard: DashboardView(openChampSelect: openChampSelect)
        case .builds: BuildsView(selection: $buildChampion)
        case .tierList: TierListView { id in buildChampion = id; page = .builds }
        case .history: HistoryView()
        case .lookup: LookupView()
        case .tools: ToolsView(openChampSelect: openChampSelect)
        }
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(Localizer.self) private var localizer
    @Binding var page: Page
    var openChampSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AppMark(size: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text("UP!").font(.title3.weight(.black)).foregroundStyle(Theme.text)
                    Text(tr("League companion")).font(.caption2).foregroundStyle(Theme.textMuted)
                }
            }
            .padding(.top, 44).padding(.horizontal, 18).padding(.bottom, 20)

            if model.isInChampSelect {
                Button(action: openChampSelect) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.fill")
                        Text(tr("Champ select is live")).font(.callout.weight(.semibold))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(LinearGradient(colors: [Theme.accentBright, Theme.accent], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12).padding(.bottom, 14)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Page.groups, id: \.0) { group, pages in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group).eyebrow().padding(.horizontal, 12).padding(.bottom, 4)
                            ForEach(pages) { item in row(item) }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }

            Spacer(minLength: 0)
            languageMenu
            profileChip
        }
        .frame(width: 236)
        .background(Theme.sidebar)
    }

    private var languageMenu: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button { localizer.language = language } label: {
                    Text("\(language.flag)  \(language.nativeName)")
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(localizer.language.flag)
                Text(localizer.language.nativeName).font(.callout).foregroundStyle(Theme.textSecondary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.hairline))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .padding(.horizontal, 12).padding(.bottom, 12)
        .help(tr("Language"))
    }

    private func row(_ item: Page) -> some View {
        let active = page == item
        return Button { withAnimation(.snappy(duration: 0.18)) { page = item } } label: {
            HStack(spacing: 11) {
                Image(systemName: item.symbol).font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                    .foregroundStyle(active ? Theme.accentBright : Theme.textMuted)
                Text(item.title).font(.system(size: 13, weight: active ? .semibold : .medium))
                    .foregroundStyle(active ? Theme.text : Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.accent.opacity(0.28), Theme.accent.opacity(0.08)], startPoint: .leading, endPoint: .trailing))
                        .overlay(alignment: .leading) {
                            Capsule().fill(Theme.accentBright).frame(width: 3, height: 16).offset(x: -1)
                        }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var profileChip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
            HStack(spacing: 10) {
                LCUImage(path: model.me?.profileIconId.map { "/lol-game-data/assets/v1/profile-icons/\($0).jpg" }, size: 34, corner: 17)
                    .overlay(Circle().strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.me?.gameName ?? tr("Not connected")).font(.callout.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    HStack(spacing: 5) {
                        Circle().fill(model.connection == .connected ? Theme.good : Theme.warning).frame(width: 6, height: 6)
                        Text(model.connection == .connected ? model.phaseTitle : tr("Looking for client…")).font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                SettingsLink {
                    Image(systemName: "gearshape.fill").foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help(tr("Settings"))
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
    }
}

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    var openChampSelect: () -> Void

    var body: some View {
        @Bindable var settings = model.settings
        Text(model.connection == .connected ? "\(model.me?.riotId ?? "") · \(model.phaseTitle)" : tr("Client not found"))
        Divider()
        Toggle(tr("Auto-accept"), isOn: $settings.autoAccept)
        Toggle(tr("Auto runes"), isOn: $settings.autoRunes)
        Toggle(tr("Open champ select window automatically"), isOn: $settings.autoOpenChampSelect)
        Toggle(tr("In-game overlay"), isOn: $settings.showOverlay)
        Divider()
        Button(tr("Open champ select window"), action: openChampSelect)
        Button(tr("Accept match")) {
            Task { await model.perform(tr("Match accepted")) { try await $0.post("/lol-matchmaking/v1/ready-check/accept") } }
        }
        Button(tr("Show UP!")) { NSApp.activate(ignoringOtherApps: true) }
        Divider()
        Button(tr("Quit UP!")) { NSApp.terminate(nil) }
    }
}

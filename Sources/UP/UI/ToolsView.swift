import SwiftUI

struct ToolsView: View, Equatable {
    @Environment(AppModel.self) private var model
    var openChampSelect: () -> Void
    @State private var tab: Tab = .game
    @State private var queueId = 420
    @State private var queues: [ClientTools.Queue] = []
    @State private var botDifficulty = "MEDIUM"
    @State private var pickMode = 1
    @State private var confirmRestart = false
    @State private var confirmDodge = false

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { true }

    enum Tab: Hashable { case game, profile, social, secret }

    private let fallbackQueues: [(Int, String)] = [
        (420, tr("Ranked Solo")), (440, tr("Ranked Flex")), (400, tr("Normal Draft")), (490, tr("Quickplay")),
        (450, "ARAM"), (1700, tr("Arena")), (1900, "URF"), (830, tr("Co-op vs AI")),
    ]

    var body: some View {
        Screen(title: tr("Tools"), subtitle: tr("Control the client through its official local API")) {
            Segmented(options: [(Tab.game, tr("Game")), (.profile, tr("Profile")), (.social, tr("Friends & loot")), (.secret, tr("Secret"))], selection: $tab)
        } content: {
            switch tab {
            case .game: gameTools
            case .profile: ProfileTools()
            case .social: SocialTools()
            case .secret: SecretTools()
            }
        }
        .confirmationDialog(tr("Restart the client UI?"), isPresented: $confirmRestart) {
            Button(tr("Restart")) {
                Task { await model.perform(tr("Client UI restarted")) { try await $0.post("/riotclient/kill-and-restart-ux") } }
            }
        }
        .confirmationDialog(tr("Dodge champion select?"), isPresented: $confirmDodge) {
            Button(tr("Dodge"), role: .destructive) {
                Task { await model.perform(tr("Champion select left")) { try await ClientTools.dodge(client: $0) } }
            }
        } message: {
            Text(tr("You leave champion select without closing the client. The usual dodge penalty still applies."))
        }
        .task(id: model.connection) {
            guard let client = model.client, let loaded = try? await ClientTools.queues(client: client), !loaded.isEmpty else { return }
            queues = loaded
            if !loaded.contains(where: { $0.id == queueId }) { queueId = loaded.first { $0.id == 420 }?.id ?? loaded[0].id }
        }
    }

    @ViewBuilder
    private var gameTools: some View {
        HStack(alignment: .top, spacing: Theme.gap) {
            lobbyPanel
            Panel(title: tr("Quick actions"), symbol: "bolt.fill") {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 8) {
                    action(tr("Accept match"), "checkmark.circle") { try await $0.post("/lol-matchmaking/v1/ready-check/accept") }
                    action(tr("Play again"), "arrow.uturn.backward") { try await $0.post("/lol-lobby/v2/play-again") }
                    action(tr("Skip post-game stats"), "xmark.rectangle") { try await $0.post("/lol-end-of-game/v1/state/dismiss-stats") }
                    action(tr("Reconnect"), "arrow.triangle.2.circlepath") { try await $0.post("/lol-gameflow/v1/reconnect") }
                    action(tr("Leave lobby"), "rectangle.portrait.and.arrow.right") { try await $0.delete("/lol-lobby/v2/lobby") }
                    action(tr("ARAM reroll"), "dice") { try await $0.post("/lol-champ-select/v1/session/my-selection/reroll") }
                    action(tr("Reroll for the team"), "gift") { try await ClientTools.rerollForTeam(client: $0) }
                        .help(tr("Rerolls and takes your champion back from the bench, so the new one is left to your teammates"))
                    Button { confirmDodge = true } label: {
                        Label(tr("Dodge"), systemImage: "figure.walk.departure").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.secondary)
                    .help(tr("Leave champion select without closing the client"))
                }
            }
        }
        HStack(alignment: .top, spacing: Theme.gap) {
            Panel(title: tr("Champ select assistant"), symbol: "binoculars.fill") {
                Text(tr("Try the assistant window with a sample draft, no game needed.")).font(.callout).foregroundStyle(Theme.textSecondary)
                HStack {
                    Button { model.startPreview(); openChampSelect() } label: { Label(tr("Preview champ select"), systemImage: "eye") }
                        .buttonStyle(.primary).disabled(model.connection != .connected)
                    Button(action: openChampSelect) { Label(tr("Open window"), systemImage: "macwindow") }.buttonStyle(.secondary)
                }
            }
            Panel(title: tr("Maintenance"), symbol: "wrench.and.screwdriver.fill") {
                HStack {
                    Button { Task { await model.perform(tr("UP! rune pages deleted")) { _ = try await ClientActions.deleteToolkitPages(client: $0) } } } label: {
                        Label(tr("Delete “%@” rune pages", ClientActions.pagePrefix), systemImage: "trash")
                    }
                    .buttonStyle(.secondary)
                    Button { confirmRestart = true } label: { Label(tr("Restart client UI"), systemImage: "arrow.clockwise") }
                        .buttonStyle(.secondary)
                    Spacer()
                }
                Text(tr("Restarting the UI helps when the client freezes. Your queue and account are unaffected.")).font(.caption).foregroundStyle(Theme.textMuted)
            }
        }
        Panel(title: tr("In-game HUD"), symbol: "rectangle.on.rectangle") {
            Text(tr("The HUD appears over the game by itself when a match starts: dragon, Baron and inhibitor timers, every enemy with level, respawn timer and all items (counter items outlined), your next item and CS per minute, and pop-up alerts.")).font(.callout).foregroundStyle(Theme.textSecondary)
            HStack {
                Button { model.startHUDPreview() } label: { Label(tr("Preview in-game HUD"), systemImage: "play.rectangle") }
                    .buttonStyle(.primary)
                if model.isHUDPreview { Button(tr("Stop preview")) { model.endHUDPreview() }.buttonStyle(.secondary) }
                Spacer()
                Text(tr("⌃⇧H show or hide · ⇧Tab match overview")).font(.caption).foregroundStyle(Theme.textMuted)
            }
        }
    }

    private var lobbyPanel: some View {
        Panel(title: tr("Lobby & queue"), symbol: "person.3.fill") {
            Picker(tr("Mode"), selection: $queueId) {
                if queues.isEmpty {
                    ForEach(fallbackQueues, id: \.0) { Text($0.1).tag($0.0) }
                } else {
                    queueSection("PvP", queues.filter { $0.isCustom != true && $0.category != "VersusAi" })
                    queueSection(tr("Co-op vs AI"), queues.filter { $0.category == "VersusAi" })
                    queueSection(tr("Custom games"), queues.filter { $0.isCustom == true })
                }
            }
            .labelsHidden().handCursor()
            HStack {
                Button(tr("Create lobby")) { Task { await createLobby() } }
                    .buttonStyle(.primary)
                Button(tr("Find match")) {
                    Task { await model.perform(tr("Queue started")) { try await $0.post("/lol-lobby/v2/lobby/matchmaking/search") } }
                }
                .buttonStyle(.secondary)
                Button(tr("Cancel")) {
                    Task { await model.perform(tr("Queue cancelled")) { try await $0.delete("/lol-lobby/v2/lobby/matchmaking/search") } }
                }
                .buttonStyle(.secondary)
            }
            if let queue = queues.first(where: { $0.id == queueId }), queue.isCustom == true {
                if queue.gameMode != "PRACTICETOOL" {
                    optionRow(tr("Pick mode")) {
                        Picker(tr("Pick mode"), selection: $pickMode) {
                            ForEach(pickModes, id: \.0) { Text($0.1).tag($0.0) }
                        }
                        .labelsHidden().fixedSize().handCursor()
                    }
                }
                optionRow(tr("Bots")) {
                    Segmented(options: [("EASY", tr("Beginner")), ("MEDIUM", tr("Intermediate"))], selection: $botDifficulty)
                    Button { Task { await addBots(team: "200") } } label: { Label(tr("Enemy team"), systemImage: "cpu") }
                        .buttonStyle(.secondary)
                    Button { Task { await addBots(team: "100") } } label: { Label(tr("Your team"), systemImage: "cpu") }
                        .buttonStyle(.secondary)
                }
            }
        }
        .onChange(of: queueId) {
            let mode = queues.first { $0.id == queueId }?.gameTypeConfig?.id
            pickMode = pickModes.contains { $0.0 == mode } ? mode ?? 1 : 1
        }
    }

    private var pickModes: [(Int, String)] {
        [(1, tr("Blind pick")), (2, tr("Draft")), (4, tr("All random")), (6, tr("Tournament draft"))]
    }

    private func optionRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.callout).foregroundStyle(Theme.textSecondary).frame(width: 80, alignment: .leading)
            content()
        }
    }

    @ViewBuilder
    private func queueSection(_ title: String, _ queues: [ClientTools.Queue]) -> some View {
        if !queues.isEmpty {
            Section(title) { ForEach(queues) { Text($0.title).tag($0.id) } }
        }
    }

    private func createLobby() async {
        let queue = queues.first { $0.id == queueId }
        let name = tr("%@'s game", model.me?.gameName ?? "UP!")
        let mode = queue?.isCustom == true && queue?.gameMode != "PRACTICETOOL" ? pickMode : nil
        await model.perform(tr("Lobby created")) { client in
            if let queue {
                try await ClientTools.createLobby(queue, name: name, pickMode: mode, client: client)
            } else {
                try await client.post("/lol-lobby/v2/lobby", ["queueId": queueId])
            }
        }
    }

    private func addBots(team: String) async {
        guard let client = model.client else { return model.notify(tr("Client is not connected"), .warning) }
        do {
            let added = try await ClientTools.addBots(difficulty: botDifficulty, team: team, client: client)
            model.notify(team == "100" ? tr("%d bots joined your team", added) : tr("%d bots joined the enemy team", added), .success)
        } catch {
            model.notify(tr("%@ failed: %@", tr("Adding bots"), error.localizedDescription), .warning)
        }
    }

    private func action(_ title: String, _ symbol: String, _ call: @escaping (LCUClient) async throws -> Void) -> some View {
        Button { Task { await model.perform(title, call) } } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.secondary)
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Localizer.self) private var localizer

    var body: some View {
        @Bindable var settings = model.settings
        @Bindable var localizer = localizer
        Form {
            Section(tr("Appearance")) {
                Picker(tr("Language"), selection: $localizer.language) {
                    ForEach(AppLanguage.allCases) { Text("\($0.flag)  \($0.nativeName)").tag($0) }
                }
                Picker(tr("Navigation style"), selection: $settings.navigationStyle) {
                    ForEach(NavigationStyle.allCases) { Text($0.title).tag($0) }
                }
                Text(tr("⌘⇧N switches to the next style right away, so you can compare them.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(tr("Match found")) {
                Toggle(tr("Accept matches automatically"), isOn: $settings.autoAccept)
                LabeledContent(tr("Accept delay")) {
                    Slider(value: $settings.acceptDelay, in: 0...8, step: 0.5) { Text("\(decimal(settings.acceptDelay)) s") }
                        .frame(width: 240)
                }
                Toggle(tr("Sound and Dock alert (match found, your turn)"), isOn: $settings.soundAlerts)
                Toggle(tr("Press “Play again” after each game"), isOn: $settings.autoPlayAgain)
            }
            Section(tr("Champ select")) {
                Toggle(tr("Open the champ select window automatically"), isOn: $settings.autoOpenChampSelect)
                Toggle(tr("Scout teammates"), isOn: $settings.scoutTeam)
            }
            Section(tr("Runes, spells, items")) {
                Toggle(tr("Import runes automatically"), isOn: $settings.autoRunes)
                Picker(tr("Rune source"), selection: $settings.runeSource) {
                    ForEach(RuneSource.allCases) { Text($0.title).tag($0) }
                }
                Toggle(tr("Import on hover (not only after lock-in)"), isOn: $settings.importOnHover)
                Toggle(tr("Overwrite the current page when none is free"), isOn: $settings.allowOverwritePage)
                Toggle(tr("Set summoner spells"), isOn: $settings.autoSpells)
                Toggle(tr("Flash on F (off = D)"), isOn: $settings.flashOnF)
                Toggle(tr("Save item sets from op.gg"), isOn: $settings.autoItemSets)
            }
            Section(tr("In-game HUD")) {
                Toggle(tr("Show the HUD as soon as a game starts"), isOn: $settings.showOverlay)
                Toggle(tr("Compact HUD (timers only)"), isOn: $settings.hudCompact)
                Toggle(tr("Pop-up alerts"), isOn: $settings.hudToasts)
                Text(tr("The HUD only appears while League of Legends is in front. Drag it anywhere, × hides it, ⌃⇧H brings it back and ⇧Tab switches to the match overview. Use windowed or borderless mode in the game.")).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text(tr("UP! only uses the client's official local API (LCU) and the Live Client Data API. It never reads or modifies game memory."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .tint(Theme.accent)
        .frame(width: 580, height: 720)
    }
}

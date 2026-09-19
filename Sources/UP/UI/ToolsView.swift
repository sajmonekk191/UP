import SwiftUI

struct ToolsView: View {
    @Environment(AppModel.self) private var model
    var openChampSelect: () -> Void
    @State private var statusMessage = ""
    @State private var availability = "chat"
    @State private var queueId = 420
    @State private var confirmRestart = false

    private let queues: [(Int, String)] = [
        (420, "Ranked Solo/Duo"), (440, "Ranked Flex"), (400, "Normal Draft"), (490, "Quickplay"),
        (450, "ARAM"), (1700, "Arena"), (1900, "URF"), (830, "Co-op vs AI"),
    ]

    var body: some View {
        Screen(title: tr("Tools"), subtitle: tr("Control the client through its official local API")) {
            HStack(alignment: .top, spacing: Theme.gap) {
                Panel(title: tr("Lobby & queue"), symbol: "person.3.fill") {
                    Picker(tr("Mode"), selection: $queueId) {
                        ForEach(queues, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .labelsHidden()
                    HStack {
                        Button(tr("Create lobby")) {
                            Task { await model.perform(tr("Lobby created")) { try await $0.post("/lol-lobby/v2/lobby", ["queueId": queueId]) } }
                        }
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
                }
                Panel(title: tr("Quick actions"), symbol: "bolt.fill") {
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 8) {
                        action(tr("Accept match"), "checkmark.circle") { try await $0.post("/lol-matchmaking/v1/ready-check/accept") }
                        action(tr("Play again"), "arrow.uturn.backward") { try await $0.post("/lol-lobby/v2/play-again") }
                        action(tr("Skip post-game stats"), "xmark.rectangle") { try await $0.post("/lol-end-of-game/v1/state/dismiss-stats") }
                        action(tr("Reconnect"), "arrow.triangle.2.circlepath") { try await $0.post("/lol-gameflow/v1/reconnect") }
                    }
                }
            }
            HStack(alignment: .top, spacing: Theme.gap) {
                Panel(title: tr("Chat & status"), symbol: "bubble.left.and.bubble.right.fill") {
                    HStack {
                        TextField(tr("Status message"), text: $statusMessage).textFieldStyle(.plain).foregroundStyle(Theme.text)
                            .padding(9).panelBackground(Theme.raised, radius: 8)
                        Button(tr("Set")) {
                            Task { await model.perform(tr("Status updated")) { try await $0.put("/lol-chat/v1/me", ["statusMessage": statusMessage]) } }
                        }
                        .buttonStyle(.primary)
                    }
                    Segmented(options: [("chat", tr("Online")), ("away", tr("Away")), ("mobile", tr("Mobile")), ("offline", tr("Offline"))],
                              selection: Binding(get: { availability }, set: { value in
                                  availability = value
                                  Task { await model.perform(tr("Availability changed")) { try await $0.put("/lol-chat/v1/me", ["availability": value]) } }
                              }))
                }
                Panel(title: tr("Champ select assistant"), symbol: "binoculars.fill") {
                    Text(tr("Try the assistant window with a sample draft, no game needed.")).font(.callout).foregroundStyle(Theme.textSecondary)
                    HStack {
                        Button { model.startPreview(); openChampSelect() } label: { Label(tr("Preview champ select"), systemImage: "eye") }
                            .buttonStyle(.primary).disabled(model.connection != .connected)
                        Button(action: openChampSelect) { Label(tr("Open window"), systemImage: "macwindow") }.buttonStyle(.secondary)
                    }
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
        .confirmationDialog(tr("Restart the client UI?"), isPresented: $confirmRestart) {
            Button(tr("Restart")) {
                Task { await model.perform(tr("Client UI restarted")) { try await $0.post("/riotclient/kill-and-restart-ux") } }
            }
        }
        .task {
            guard let client = model.client,
                  let data = try? await client.request("GET", "/lol-chat/v1/me"),
                  let me = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            statusMessage = me["statusMessage"] as? String ?? ""
            availability = me["availability"] as? String ?? "chat"
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
            Section(tr("Language")) {
                Picker(tr("Language"), selection: $localizer.language) {
                    ForEach(AppLanguage.allCases) { Text("\($0.flag)  \($0.nativeName)").tag($0) }
                }
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
            Section(tr("In game")) {
                Toggle(tr("Show the overlay during games"), isOn: $settings.showOverlay)
                Toggle(tr("Overlay lets mouse clicks through"), isOn: $settings.overlayClickThrough)
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

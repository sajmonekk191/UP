import SwiftUI

/// Profile icon, background, friends-list card and chat status tools.
struct ProfileTools: View {
    @Environment(AppModel.self) private var model
    @State private var statusMessage = ""
    @State private var availability = "chat"
    @State private var chatIcon: Int?
    @State private var sheet: Sheet?
    @State private var rankQueue = "RANKED_SOLO_5x5"
    @State private var rankTier = "GOLD"
    @State private var rankDivision = "I"
    @State private var crystal = "GOLD"
    @State private var points = ""
    @State private var mastery = ""

    enum Sheet: String, Identifiable {
        case profileIcon, chatIcon, background
        var id: String { rawValue }
    }

    private static let tiers = ["IRON", "BRONZE", "SILVER", "GOLD", "PLATINUM", "EMERALD", "DIAMOND", "MASTER", "GRANDMASTER", "CHALLENGER"]
    private static let divisions = ["I", "II", "III", "IV"]

    private var rankQueues: [(String, String)] { [("RANKED_SOLO_5x5", tr("Ranked Solo")), ("RANKED_FLEX_SR", tr("Ranked Flex")), ("RANKED_TFT", "TFT")] }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            HStack(alignment: .top, spacing: Theme.gap) {
                lookPanel
                statusPanel
            }
            cardPanel
        }
        .sheet(item: $sheet) { sheet in
            Group {
                switch sheet {
                case .profileIcon:
                    IconPicker(title: tr("Profile icon"), owned: true) { id in
                        await model.perform(tr("Profile icon changed")) { try await ClientTools.setProfileIcon(id, client: $0) }
                    }
                case .chatIcon:
                    IconPicker(title: tr("Friends-list icon"), owned: false) { id in
                        await model.perform(tr("Friends-list icon changed")) { try await ClientTools.setChatIcon(id, client: $0) }
                        await loadChat()
                    }
                case .background:
                    BackgroundPicker { skinId in
                        await model.perform(tr("Profile background changed")) { try await ClientTools.setBackground(skinId: skinId, client: $0) }
                    }
                }
            }
            .environment(model)
        }
        .task(id: model.connection) { await loadChat() }
    }

    private var lookPanel: some View {
        Panel(title: tr("Look"), symbol: "person.crop.circle.fill") {
            lookRow(icon: model.me?.profileIconId, title: tr("Profile icon"), detail: tr("Any icon you own.")) { sheet = .profileIcon }
            lookRow(icon: chatIcon, title: tr("Friends-list icon"), detail: tr("Any icon in the game, shown next to your name in your friends' lists.")) { sheet = .chatIcon }
            lookRow(icon: nil, title: tr("Profile background"), detail: tr("Splash art of any champion skin behind your profile.")) { sheet = .background }
            lookRow(icon: nil, symbol: "flag.fill", title: tr("Banner"), detail: tr("Shows last season's banner, or no banner at all if you were unranked last season."), button: tr("Use")) {
                Task { await model.perform(tr("Banner changed")) { try await ClientTools.showLastSeasonBanner(client: $0) } }
            }
        }
    }

    private func lookRow(icon: Int?, symbol: String = "photo.fill", title: String, detail: String, button: String = tr("Change…"), action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            if let icon {
                LCUImage(path: "/lol-game-data/assets/v1/profile-icons/\(icon).jpg", size: 40, corner: 20)
            } else {
                Image(systemName: symbol).foregroundStyle(Theme.accentBright)
                    .frame(width: 40, height: 40).background(Theme.raised, in: Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                Text(detail).font(.caption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(button, action: action).buttonStyle(.secondary).disabled(model.connection != .connected)
        }
    }

    private var statusPanel: some View {
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
    }

    private var cardPanel: some View {
        Panel(title: tr("Friends-list card"), symbol: "person.text.rectangle.fill") {
            Text(tr("Changes what friends see when they hover over you in their friends list, until the client updates it again."))
                .font(.caption).foregroundStyle(Theme.textSecondary)
            cardRow(tr("Rank")) {
                Segmented(options: rankQueues, selection: $rankQueue)
                tierMenu($rankTier)
                if !["MASTER", "GRANDMASTER", "CHALLENGER"].contains(rankTier) {
                    Segmented(options: Self.divisions.map { ($0, $0) }, selection: $rankDivision)
                }
                Spacer(minLength: 8)
                Button(tr("Hide")) { card(["rankedLeagueQueue": "", "rankedLeagueTier": "", "rankedLeagueDivision": ""], tr("Rank hidden")) }
                    .buttonStyle(.secondary)
                Button(tr("Show")) {
                    let division = ["MASTER", "GRANDMASTER", "CHALLENGER"].contains(rankTier) ? "I" : rankDivision
                    card(["rankedLeagueQueue": rankQueue, "rankedLeagueTier": rankTier, "rankedLeagueDivision": division], tr("Rank changed"))
                }
                .buttonStyle(.primary)
            }
            cardRow(tr("Challenges")) {
                tierMenu($crystal)
                numberField($points, tr("Points"))
                Spacer(minLength: 8)
                Button(tr("Set")) { card(["challengeCrystalLevel": crystal, "challengePoints": points], tr("Challenges changed")) }
                    .buttonStyle(.primary)
            }
            cardRow(tr("Mastery score")) {
                numberField($mastery, "0")
                Spacer(minLength: 8)
                Button(tr("Set")) { card(["masteryScore": mastery], tr("Mastery score changed")) }
                    .buttonStyle(.primary)
            }
            cardRow(tr("Tokens")) {
                Button(tr("Remove all")) { tokens(.none) }.buttonStyle(.secondary)
                Button(tr("Repeat the first")) { tokens(.firstThreeTimes) }.buttonStyle(.secondary)
                Button(tr("Glitched")) { tokens(.glitched) }.buttonStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
    }

    private func cardRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.callout.weight(.medium)).foregroundStyle(Theme.textSecondary).frame(width: 120, alignment: .leading)
            content()
        }
    }

    private func tierMenu(_ selection: Binding<String>) -> some View {
        Picker("", selection: selection) {
            ForEach(Self.tiers, id: \.self) { Text($0.capitalized).tag($0) }
        }
        .labelsHidden().fixedSize().handCursor()
    }

    private func numberField(_ text: Binding<String>, _ placeholder: String) -> some View {
        TextField(placeholder, text: text).textFieldStyle(.plain).foregroundStyle(Theme.text).frame(width: 90)
            .padding(.horizontal, 9).padding(.vertical, 6).panelBackground(Theme.raised, radius: 8)
            .onChange(of: text.wrappedValue) { _, value in
                let digits = value.filter(\.isNumber)
                if digits != value { text.wrappedValue = digits }
            }
    }

    private func card(_ values: [String: String], _ success: String) {
        Task { await model.perform(success) { try await ClientTools.setCard(values, client: $0) } }
    }

    private func tokens(_ tokens: ClientTools.Tokens) {
        Task { await model.perform(tr("Tokens changed")) { try await ClientTools.setTokens(tokens, client: $0) } }
    }

    private func loadChat() async {
        guard let client = model.client,
              let data = try? await client.request("GET", "/lol-chat/v1/me"),
              let me = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        statusMessage = me["statusMessage"] as? String ?? ""
        availability = me["availability"] as? String ?? "chat"
        chatIcon = me["icon"] as? Int
        let lol = me["lol"] as? [String: String] ?? [:]
        if let queue = lol["rankedLeagueQueue"], rankQueues.contains(where: { $0.0 == queue }) { rankQueue = queue }
        if let tier = lol["rankedLeagueTier"], Self.tiers.contains(tier) { rankTier = tier }
        if let division = lol["rankedLeagueDivision"], Self.divisions.contains(division) { rankDivision = division }
        if let level = lol["challengeCrystalLevel"], Self.tiers.contains(level) { crystal = level }
        points = lol["challengePoints"] ?? ""
        mastery = lol["masteryScore"] ?? ""
    }
}

/// Sheet with a title, a search field and scrolling content, for picking icons, skins or champions.
struct PickerSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @Binding var search: String
    var back: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let back {
                    Button(action: back) { Image(systemName: "chevron.left").font(.body.weight(.semibold)).foregroundStyle(Theme.accentBright) }
                        .buttonStyle(.plain).handCursor()
                }
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textMuted)
                    TextField(tr("Search"), text: $search).textFieldStyle(.plain).foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 10).frame(width: 240, height: 32)
                .panelBackground(Theme.surface, radius: 9)
                Button(tr("Close")) { dismiss() }.buttonStyle(.secondary).keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            ScrollView { content.padding(16) }
        }
        .frame(width: 780, height: 580)
        .background(Theme.background)
    }
}

/// Searchable grid of profile icons that applies the one picked.
private struct IconPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let title: String
    let owned: Bool
    let apply: (Int) async -> Void
    @State private var icons: [ClientTools.Icon]?
    @State private var search = ""

    var body: some View {
        PickerSheet(title: title, search: $search) {
            if let icons {
                let shown = filtered(icons)
                if shown.isEmpty {
                    Text(tr("No icons found.")).font(.callout).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity).padding(.vertical, 40)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 12)], spacing: 12) {
                        ForEach(shown) { icon in
                            Button { Task { await apply(icon.id); dismiss() } } label: {
                                LCUImage(path: "/lol-game-data/assets/v1/profile-icons/\(icon.id).jpg", size: 64, corner: 32)
                            }
                            .buttonStyle(.plain).handCursor()
                            .help(icon.title.map { "\($0) · #\(icon.id)" } ?? "#\(icon.id)")
                        }
                    }
                }
            } else {
                LoadingNote(text: tr("Loading icons…")).frame(maxWidth: .infinity).padding(.vertical, 40)
            }
        }
        .task {
            guard let client = model.client else { return icons = [] }
            if owned {
                icons = (try? await ClientTools.ownedIcons(client: client)) ?? []
            } else {
                icons = (try? await ClientTools.allIcons(client: client)) ?? []
            }
        }
    }

    private func filtered(_ icons: [ClientTools.Icon]) -> [ClientTools.Icon] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return icons }
        return icons.filter { String($0.id).hasPrefix(query) || ($0.title ?? "").localizedCaseInsensitiveContains(query) }
    }
}

/// Champion grid, then that champion's skins, to set the splash art behind the profile.
private struct BackgroundPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let apply: (Int) async -> Void
    @State private var champion: Int?
    @State private var search = ""

    var body: some View {
        PickerSheet(title: champion.map { model.gameData.championName($0) } ?? tr("Profile background"), search: $search,
                    back: champion == nil ? nil : { champion = nil; search = "" }) {
            if let champion { skins(champion) } else { champions }
        }
        .task(id: champion) {
            if let champion { _ = await model.gameData.detail(champion, client: model.client) }
        }
    }

    private var champions: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
            ForEach(model.gameData.sortedChampions.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }, id: \.id) { champion in
                Button { self.champion = champion.id; search = "" } label: {
                    VStack(spacing: 5) {
                        ChampionIcon(id: champion.id, size: 52)
                        Text(champion.name).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity).contentShape(Rectangle())
                }
                .buttonStyle(.plain).handCursor()
            }
        }
    }

    @ViewBuilder
    private func skins(_ championId: Int) -> some View {
        if let skins = model.gameData.details[championId]?.skins {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 14) {
                ForEach(Array(skins.filter { search.isEmpty || ($0.name ?? "").localizedCaseInsensitiveContains(search) }.enumerated()), id: \.offset) { _, skin in
                    Button { if let id = skin.id { Task { await apply(id); dismiss() } } } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Color.clear
                                .overlay { LCUImage(path: skin.tilePath, size: nil, corner: 0, fill: Theme.surface, contentMode: .fill).allowsHitTesting(false) }
                                .frame(height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline))
                            Text(skin.name ?? "").font(.caption.weight(.medium)).foregroundStyle(Theme.text).lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).handCursor()
                }
            }
        } else {
            LoadingNote(text: tr("Loading skins…")).frame(maxWidth: .infinity).padding(.vertical, 40)
        }
    }
}

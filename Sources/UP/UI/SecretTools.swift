import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Answers friend requests in bulk and turns loot into Blue Essence, Orange Essence or keys.
struct SocialTools: View {
    @Environment(AppModel.self) private var model
    @State private var requests: Int?
    @State private var loot: [ClientTools.LootItem]?
    @State private var riotPoints: Int?
    @State private var confirmDecline = false
    @State private var confirmDisenchant = false
    @State private var confirmCosmetics = false

    var body: some View {
        let shards = ClientTools.ownedChampionShards(in: loot ?? [])
        let shardCount = shards.reduce(0) { $0 + max($1.count ?? 1, 1) }
        let essence = shards.reduce(0) { $0 + ($1.disenchantValue ?? 0) * max($1.count ?? 1, 1) }
        let cosmetics = ClientTools.ownedCosmeticShards(in: loot ?? [])
        let cosmeticCount = cosmetics.reduce(0) { $0 + max($1.count ?? 1, 1) }
        let orange = cosmetics.reduce(0) { $0 + ($1.disenchantValue ?? 0) * max($1.count ?? 1, 1) }
        let fragments = ClientTools.keyFragments(in: loot ?? [])
        HStack(alignment: .top, spacing: Theme.gap) {
            Panel(title: tr("Friend requests"), symbol: "person.crop.circle.badge.plus") {
                Text(requests.map { $0 == 0 ? tr("No friend requests are waiting.") : tr("%d friend requests are waiting.", $0) } ?? tr("Loading…"))
                    .font(.callout).foregroundStyle(Theme.textSecondary)
                HStack {
                    Button(tr("Accept all")) { Task { await answer(accept: true) } }
                        .buttonStyle(.primary).disabled((requests ?? 0) == 0)
                    Button(tr("Decline all")) { confirmDecline = true }
                        .buttonStyle(.secondary).disabled((requests ?? 0) == 0)
                }
            }
            Panel(title: tr("Loot"), symbol: "shippingbox.fill") {
                if let loot {
                    HStack(spacing: 18) {
                        KeyValue(key: "RP", value: riotPoints.map { compact(Double($0)) } ?? "—")
                        KeyValue(key: tr("Blue Essence"), value: compact(Double(ClientTools.currency("CURRENCY_champion", in: loot))))
                        KeyValue(key: tr("Orange Essence"), value: compact(Double(ClientTools.currency("CURRENCY_cosmetic", in: loot))))
                        KeyValue(key: tr("Mythic Essence"), value: compact(Double(ClientTools.currency("CURRENCY_mythic", in: loot))))
                    }
                }
                lootRow(tr("Shards of champions you own"),
                        shards.isEmpty ? tr("None right now.") : tr("%d shards · %@ Blue Essence", shardCount, compact(Double(essence))),
                        tr("Disenchant"), enabled: !shards.isEmpty) { confirmDisenchant = true }
                lootRow(tr("Skins, wards, icons and emotes you own"),
                        cosmetics.isEmpty ? tr("None right now.") : tr("%d shards · %@ Orange Essence", cosmeticCount, compact(Double(orange))),
                        tr("Disenchant"), enabled: !cosmetics.isEmpty) { confirmCosmetics = true }
                lootRow(tr("Key fragments"), tr("%d fragments make %d keys.", fragments, fragments / 3), tr("Craft keys"), enabled: fragments >= 3) {
                    Task {
                        await model.perform(tr("Keys crafted")) { try await ClientTools.craftKeys(fragments: fragments, client: $0) }
                        await reload()
                    }
                }
            }
        }
        .confirmationDialog(tr("Decline all friend requests?"), isPresented: $confirmDecline) {
            Button(tr("Decline all"), role: .destructive) { Task { await answer(accept: false) } }
        }
        .confirmationDialog(tr("Disenchant %d shards for %@ Blue Essence?", shardCount, compact(Double(essence))), isPresented: $confirmDisenchant) {
            Button(tr("Disenchant"), role: .destructive) { disenchant(shards) }
        } message: {
            Text(tr("Only shards of champions you already own. This cannot be undone."))
        }
        .confirmationDialog(tr("Disenchant %d shards for %@ Orange Essence?", cosmeticCount, compact(Double(orange))), isPresented: $confirmCosmetics) {
            Button(tr("Disenchant"), role: .destructive) { disenchant(cosmetics) }
        } message: {
            Text(tr("Only skins, wards, icons and emotes you already own. This cannot be undone."))
        }
        .task(id: model.connection) { await reload() }
    }

    private func lootRow(_ title: String, _ detail: String, _ button: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                Text(detail).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            Button(button, action: action).buttonStyle(.secondary).disabled(!enabled)
        }
    }

    private func disenchant(_ items: [ClientTools.LootItem]) {
        Task {
            await model.perform(tr("Shards disenchanted")) { try await ClientTools.disenchant(items, client: $0) }
            await reload()
        }
    }

    private func answer(accept: Bool) async {
        await model.perform(accept ? tr("Friend requests accepted") : tr("Friend requests declined")) {
            _ = try await ClientTools.answerFriendRequests(accept: accept, client: $0)
        }
        await reload()
    }

    private func reload() async {
        guard let client = model.client else { return }
        async let waiting = try? ClientTools.incomingFriendRequests(client: client)
        async let items = try? ClientTools.loot(client: client)
        async let points = try? ClientTools.riotPoints(client: client)
        requests = await waiting ?? 0
        loot = await items ?? []
        riotPoints = await points
    }
}

/// Account facts, client window control, settings backup and other extras the League client does not offer itself.
struct SecretTools: View {
    @Environment(AppModel.self) private var model
    @State private var collection: [ClientTools.Champion]?
    @State private var showCollection = false
    @State private var progress: ClientTools.Progress?
    @State private var honor: ClientTools.Honor?
    @State private var backup: Data?
    @State private var confirmRestore = false
    @State private var title = "UP!"
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            HStack(alignment: .top, spacing: Theme.gap) {
                collectionPanel
                accountPanel
            }
            HStack(alignment: .top, spacing: Theme.gap) {
                clientWindowPanel
                settingsPanel
            }
            notificationPanel
        }
        .sheet(isPresented: $showCollection) { CollectionSheet(champions: collection ?? []).environment(model) }
        .confirmationDialog(tr("Replace your game settings and hotkeys with the backup?"), isPresented: $confirmRestore, presenting: backup) { data in
            Button(tr("Restore"), role: .destructive) {
                Task { await model.perform(tr("Game settings restored")) { try await ClientTools.restoreGameSettings(data, client: $0) } }
            }
        }
        .task(id: [model.me?.summonerId ?? 0, model.gameData.champions.count]) {
            guard let client = model.client, let summonerId = model.me?.summonerId, !model.gameData.champions.isEmpty else { return }
            collection = ((try? await ClientTools.collection(summonerId: summonerId, client: client)) ?? []).filter { model.gameData.champions[$0.id] != nil }
        }
        .task(id: model.connection) {
            guard let client = model.client else { return }
            async let loadedProgress = try? ClientTools.progress(client: client)
            async let loadedHonor = try? ClientTools.honor(client: client)
            progress = await loadedProgress
            honor = await loadedHonor
        }
    }

    private var collectionPanel: some View {
        Panel(title: tr("Your collection"), symbol: "books.vertical.fill") {
            if let collection {
                if let first = collection.first, let newest = collection.last {
                    let skins = collection.reduce(0) { total, champion in
                        total + (champion.skins ?? []).filter { $0.id % 1000 != 0 && $0.ownership?.owned == true }.count
                    }
                    HStack(spacing: 12) {
                        StatTile(label: tr("Champions"), value: "\(collection.count)")
                        StatTile(label: tr("Skins"), value: "\(skins)")
                    }
                    purchaseRow(tr("First champion"), first)
                    purchaseRow(tr("Newest champion"), newest)
                    Button { showCollection = true } label: { Label(tr("All purchases"), systemImage: "list.bullet") }
                        .buttonStyle(.secondary)
                } else {
                    Text(tr("No champions found.")).font(.callout).foregroundStyle(Theme.textSecondary)
                }
            } else {
                LoadingNote(text: tr("Loading your collection…"))
            }
        }
    }

    private func purchaseRow(_ title: String, _ champion: ClientTools.Champion) -> some View {
        HStack(spacing: 10) {
            ChampionIcon(id: champion.id, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).eyebrow()
                Text(champion.name).font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
            }
            Spacer(minLength: 8)
            Text(purchaseDate(champion)).font(.callout.monospacedDigit()).foregroundStyle(Theme.textSecondary)
        }
    }

    private var accountPanel: some View {
        Panel(title: tr("Account"), symbol: "person.text.rectangle.fill") {
            if let progress {
                if let level = progress.summonerLevel, let since = progress.xpSinceLastLevel, let until = progress.xpUntilNextLevel {
                    meterRow(tr("Level %d", level), tr("%@ XP to the next level", compact(Double(until))), Double(since) / Double(max(since + until, 1)))
                }
                if let rolls = progress.rerollPoints, let count = rolls.numberOfRolls, let most = rolls.maxRolls {
                    let points = rolls.currentPoints ?? 0
                    let cost = max(rolls.pointsCostToRoll ?? 1, 1)
                    meterRow(tr("ARAM rerolls: %d of %d", count, most),
                             count >= most ? tr("All rerolls are ready.") : tr("%d of %d points to the next reroll", points, cost),
                             count >= most ? 1 : Double(points) / Double(cost))
                }
                if let level = honor?.honorLevel {
                    HStack(spacing: 10) {
                        Image(systemName: "hand.thumbsup.fill").foregroundStyle(Theme.gold)
                        Text(tr("Honor level %d", level)).font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                    }
                }
            } else {
                LoadingNote(text: tr("Loading…"))
            }
        }
    }

    private func meterRow(_ title: String, _ detail: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                Spacer(minLength: 8)
                Text(detail).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Meter(value: min(max(value, 0), 1))
        }
    }

    private var clientWindowPanel: some View {
        Panel(title: tr("Client window"), symbol: "macwindow") {
            Text(tr("Closes the League client window while League keeps running, even during a game. It frees memory and your queue or game is not affected."))
                .font(.caption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button { Task { await model.perform(tr("Client window closed")) { try await $0.post("/riotclient/kill-ux") } } } label: {
                    Label(tr("Close window"), systemImage: "xmark.square")
                }
                .buttonStyle(.secondary)
                Button { Task { await model.perform(tr("Client window opened")) { try await $0.post("/riotclient/launch-ux") } } } label: {
                    Label(tr("Open window"), systemImage: "macwindow")
                }
                .buttonStyle(.secondary)
            }
            .disabled(model.connection != .connected)
        }
    }

    private var settingsPanel: some View {
        Panel(title: tr("Game settings backup"), symbol: "externaldrive.fill") {
            Text(tr("Saves your in-game settings and hotkeys to a file, so you can bring them back after a reinstall or copy them to another account."))
                .font(.caption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button { Task { await saveSettings() } } label: { Label(tr("Save to file…"), systemImage: "square.and.arrow.down") }
                    .buttonStyle(.primary)
                Button(action: openBackup) { Label(tr("Restore from file…"), systemImage: "square.and.arrow.up") }
                    .buttonStyle(.secondary)
            }
            .disabled(model.connection != .connected)
        }
    }

    private var notificationPanel: some View {
        Panel(title: tr("Client notification"), symbol: "bell.badge.fill") {
            Text(tr("Pops up a notification with your own text in the League client. Only you see it."))
                .font(.caption).foregroundStyle(Theme.textSecondary)
            TextField(tr("Title"), text: $title).textFieldStyle(.plain).foregroundStyle(Theme.text)
                .padding(9).panelBackground(Theme.raised, radius: 8)
            TextField(tr("Message"), text: $message).textFieldStyle(.plain).foregroundStyle(Theme.text)
                .padding(9).panelBackground(Theme.raised, radius: 8)
            Button { Task { await model.perform(tr("Notification sent")) { try await ClientTools.notification(title: title, text: message, client: $0) } } } label: {
                Label(tr("Send"), systemImage: "paperplane.fill")
            }
            .buttonStyle(.primary)
            .disabled(message.trimmingCharacters(in: .whitespaces).isEmpty || model.connection != .connected)
        }
    }

    private func saveSettings() async {
        guard let client = model.client else { return model.notify(tr("Client is not connected"), .warning) }
        do {
            let data = try await ClientTools.gameSettings(client: client)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "League settings.json"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url)
            model.notify(tr("Game settings saved"), .success)
        } catch {
            model.notify(tr("%@ failed: %@", tr("Game settings backup"), error.localizedDescription), .warning)
        }
    }

    private func openBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            backup = try Data(contentsOf: url)
            confirmRestore = true
        } catch {
            model.notify(tr("%@ failed: %@", tr("Game settings backup"), error.localizedDescription), .warning)
        }
    }
}

/// Owned champions with the day each was bought, oldest first.
private struct CollectionSheet: View {
    let champions: [ClientTools.Champion]
    @State private var search = ""

    var body: some View {
        PickerSheet(title: tr("All purchases"), search: $search) {
            LazyVStack(spacing: 6) {
                ForEach(Array(champions.enumerated()).filter { search.isEmpty || $0.element.name.localizedCaseInsensitiveContains(search) }, id: \.element.id) { index, champion in
                    HStack(spacing: 12) {
                        Text("\(index + 1)").font(.callout.monospacedDigit()).foregroundStyle(Theme.textMuted).frame(width: 34, alignment: .trailing)
                        ChampionIcon(id: champion.id, size: 32)
                        Text(champion.name).font(.callout.weight(.medium)).foregroundStyle(Theme.text)
                        Spacer()
                        Text(purchaseDate(champion)).font(.callout.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(index.isMultiple(of: 2) ? Theme.surface : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }
}

private func purchaseDate(_ champion: ClientTools.Champion) -> String {
    champion.purchaseDate?.formatted(.dateTime.day().month(.abbreviated).year().locale(Localizer.shared.language.locale)) ?? "—"
}

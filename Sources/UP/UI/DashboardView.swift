import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    var openChampSelect: () -> Void

    var body: some View {
        Screen(title: tr("Overview"), subtitle: model.connection != .connected ? tr("Waiting for the League client…") : model.phase == "None" ? tr("Connected to the client") : tr("Connected to the client · %@", model.phaseTitle)) {
            Button { Task { await model.refreshMyProfile() } } label: { Label(tr("Refresh"), systemImage: "arrow.clockwise") }
                .buttonStyle(.secondary)
        } content: {
            profileHero
            if let profile = model.myProfile {
                statTiles(profile)
                HStack(alignment: .top, spacing: Theme.gap) {
                    VStack(spacing: Theme.gap) {
                        DraftAssistantCard(openChampSelect: openChampSelect)
                        championsPanel(profile)
                        rolesPanel(profile)
                    }
                    VStack(spacing: Theme.gap) {
                        AutomationPanel()
                        masteryPanel
                    }
                    .frame(width: 360)
                }
            }
            LogView()
        }
    }

    private var profileHero: some View {
        let splash = model.myProfile?.champions.first.flatMap { model.gameData.details[$0.championId]?.splashPath }
        return HeroBanner(splashPath: splash, height: 190) {
            HStack(alignment: .center, spacing: 18) {
                LCUImage(path: model.me?.profileIconId.map { "/lol-game-data/assets/v1/profile-icons/\($0).jpg" }, size: 84, corner: 42)
                    .overlay(Circle().strokeBorder(LinearGradient(colors: [Theme.accentBright, Theme.accentDeep], startPoint: .top, endPoint: .bottom), lineWidth: 3))
                    .overlay(alignment: .bottom) {
                        if let level = model.me?.summonerLevel {
                            Text("\(level)").font(.caption.weight(.bold)).foregroundStyle(Theme.text)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Theme.accentDeep, in: Capsule()).overlay(Capsule().strokeBorder(Theme.accent))
                                .offset(y: 8)
                        }
                    }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(model.me?.gameName ?? "—").font(.system(size: 32, weight: .bold)).foregroundStyle(Theme.text)
                        if let tag = model.me?.tagLine { Text("#\(tag)").font(.title3).foregroundStyle(Theme.textSecondary) }
                    }
                    if let profile = model.myProfile { FlowTags(tags: profile.tags) }
                }
                Spacer()
                if let profile = model.myProfile {
                    HStack(spacing: 28) {
                        RankBlock(title: tr("Solo / Duo"), queue: profile.solo)
                        RankBlock(title: tr("Flex"), queue: profile.flex)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
                }
            }
        }
        .task(id: model.myProfile?.champions.first?.championId) {
            if let id = model.myProfile?.champions.first?.championId { _ = await model.gameData.detail(id, client: model.client) }
        }
    }

    private func statTiles(_ profile: PlayerProfile) -> some View {
        let a = profile.averages
        let kda = profile.averageKDA
        let today = profile.recentGames.filter { Calendar.current.isDateInToday($0.date ?? .distantPast) }
        let todayWins = today.filter { $0.me?.stats.win == true }.count
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
            StatTile(label: tr("Win rate"), value: percent(profile.recentWinRate, digits: 0),
                     sub: tr("%dW / %dL", profile.recentWins, profile.recentGames.count - profile.recentWins), valueColor: winRateColor(profile.recentWinRate),
                     trend: rollingWinRate(profile))
            StatTile(label: tr("Today"), value: today.isEmpty ? "—" : tr("%dW %dL", todayWins, today.count - todayWins),
                     sub: today.isEmpty ? tr("No games yet") : tr("%d games today", today.count))
            StatTile(label: "KDA", value: decimal((kda.k + kda.a) / max(kda.d, 1), 2),
                     sub: "\(decimal(kda.k)) / \(decimal(kda.d)) / \(decimal(kda.a))")
            StatTile(label: tr("CS / min"), value: decimal(a.csPerMin, 1), sub: tr("farm per minute"))
            StatTile(label: tr("Dmg / min"), value: compact(a.damagePerMin), sub: tr("to champions"))
            StatTile(label: tr("Vision / min"), value: decimal(a.visionPerMin, 2), sub: tr("%d multikills", a.multikills))
        }
    }

    /// Cumulative win rate from oldest to newest game, for the tile sparkline.
    private func rollingWinRate(_ profile: PlayerProfile) -> [Double] {
        var wins = 0.0
        return profile.recentGames.reversed().enumerated().map { index, game in
            wins += game.me?.stats.win == true ? 1 : 0
            return wins / Double(index + 1)
        }
    }

    private func championsPanel(_ profile: PlayerProfile) -> some View {
        Panel(title: tr("Most played champions"), symbol: "person.crop.square.filled.and.at.rectangle") {
            if profile.champions.isEmpty {
                Text(tr("No countable games.")).foregroundStyle(Theme.textSecondary)
            }
            ForEach(profile.champions.prefix(6)) { record in
                HStack(spacing: 12) {
                    ChampionIcon(id: record.championId, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.gameData.championName(record.championId)).font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                        Text("\(decimal(record.kda, 2)) KDA").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    .frame(width: 150, alignment: .leading)
                    WinRateMeter(winRate: record.winRate, games: record.games)
                }
            }
        }
    }

    private func rolesPanel(_ profile: PlayerProfile) -> some View {
        Panel(title: tr("Roles in recent games"), symbol: "map") {
            if profile.roleShares.isEmpty {
                Text(tr("The client does not report roles for these games.")).foregroundStyle(Theme.textSecondary)
            }
            ForEach(profile.roleShares, id: \.lane) { role in
                HStack(spacing: 10) {
                    Label(role.lane.title, systemImage: role.lane.symbol).font(.callout).foregroundStyle(Theme.text).frame(width: 110, alignment: .leading)
                    Meter(value: role.share)
                    Text(percent(role.share, digits: 0)).font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary).frame(width: 40, alignment: .trailing)
                }
            }
        }
    }

    private var masteryPanel: some View {
        Panel(title: tr("Mastery"), symbol: "star.fill") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 12) {
                ForEach(model.myMasteries.prefix(8), id: \.championId) { mastery in
                    VStack(spacing: 4) {
                        ChampionIcon(id: mastery.championId, size: 44, ring: (mastery.championLevel ?? 0) >= 10 ? Theme.gold : nil)
                        Text("M\(mastery.championLevel ?? 0)").font(.caption.weight(.bold)).foregroundStyle(Theme.gold)
                        Text(compact(Double(mastery.championPoints ?? 0))).font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }
}

/// Explains the champ select window and lets the user open or preview it.
struct DraftAssistantCard: View {
    @Environment(AppModel.self) private var model
    var openChampSelect: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(Theme.accentDeep.opacity(0.5)).frame(width: 52, height: 52)
                Image(systemName: model.isInChampSelect ? "person.2.fill" : "binoculars.fill").font(.title3).foregroundStyle(Theme.accentBright)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(model.isInChampSelect ? tr("Champ select is live") : tr("Champ select assistant")).font(.headline).foregroundStyle(Theme.text)
                Text(model.isInChampSelect
                     ? tr("Best picks, counters, bans and your game plan are ready.")
                     : tr("Waiting for your next draft. The assistant window opens by itself with best picks, counters, bans and runes."))
                    .font(.callout).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if model.isInChampSelect {
                Button(tr("Open"), action: openChampSelect).buttonStyle(.primary)
            } else {
                Button(tr("Preview")) { model.startPreview(); openChampSelect() }.buttonStyle(.secondary)
                    .disabled(model.connection != .connected)
            }
        }
        .padding(16)
        .background(LinearGradient(colors: [Theme.accentDeep.opacity(0.45), Theme.surface], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.accent.opacity(0.35)))
    }
}

struct AutomationPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Panel(title: tr("Automation"), symbol: "bolt.fill") {
            VStack(spacing: 10) {
                toggle(tr("Auto-accept"), "checkmark.circle", $settings.autoAccept)
                toggle(tr("Champ select window"), "macwindow", $settings.autoOpenChampSelect)
                toggle(tr("Import runes"), "circle.hexagongrid", $settings.autoRunes)
                toggle(tr("Summoner spells"), "sparkles", $settings.autoSpells)
                toggle(tr("Item sets"), "bag", $settings.autoItemSets)
                toggle(tr("Scout teammates"), "person.2", $settings.scoutTeam)
                toggle(tr("In-game overlay"), "rectangle.on.rectangle", $settings.showOverlay)
                toggle(tr("Sounds"), "speaker.wave.2", $settings.soundAlerts)
            }
        }
    }

    private func toggle(_ title: String, _ symbol: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.callout).foregroundStyle(Theme.accentBright).frame(width: 20)
            Text(title).font(.callout).foregroundStyle(Theme.text)
            Spacer()
            Toggle(title, isOn: binding).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}

struct LogView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Panel(title: tr("Activity"), symbol: "waveform.path.ecg") {
            if model.logs.isEmpty {
                Text(tr("No activity yet.")).foregroundStyle(Theme.textSecondary)
            }
            ForEach(model.logs.prefix(12)) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: icon(entry.kind)).foregroundStyle(color(entry.kind)).font(.caption)
                    Text(entry.text).font(.callout).foregroundStyle(Theme.text).textSelection(.enabled)
                    Spacer()
                    Text(entry.date, format: .dateTime.hour().minute().second())
                        .font(.caption.monospacedDigit()).foregroundStyle(Theme.textMuted)
                }
            }
        }
    }

    private func icon(_ kind: LogEntry.Kind) -> String {
        switch kind {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    private func color(_ kind: LogEntry.Kind) -> Color {
        switch kind {
        case .info: Theme.accentBright
        case .success: Theme.good
        case .warning: Theme.warning
        }
    }
}

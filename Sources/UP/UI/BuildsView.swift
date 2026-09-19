import SwiftUI

struct BuildsView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: Int?
    @Binding var championClass: String?
    @State private var search = ""
    @State private var lane: Lane?
    @State private var mode: QueueMode = .ranked
    @State private var build: ChampionBuild?
    @State private var riotRunes: [RuneSetup] = []
    @State private var highElo: [RuneSetup] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        HStack(spacing: 0) {
            championList
            Rectangle().fill(Theme.hairline).frame(width: 1)
            Group {
                if let championId = selection {
                    detail(championId)
                        .frame(minWidth: 0)
                        .task(id: "\(championId)-\(lane?.rawValue ?? "")-\(mode.rawValue)") { await load(championId) }
                } else {
                    EmptyState(symbol: "books.vertical.fill", title: tr("Pick a champion"),
                               message: tr("Runes, items, skill order, matchups and win rate by game length from op.gg, plus Riot's recommendations."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var championList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textMuted)
                TextField(tr("Search champion"), text: $search).textFieldStyle(.plain).foregroundStyle(Theme.text)
            }
            .padding(10)
            .panelBackground(Theme.surface, radius: 10)
            .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, championClass == nil ? 10 : 6)

            if let championClass {
                HStack {
                    Chip(text: "#\(championClass)", tone: .accent, symbol: "number")
                    Spacer()
                    Button { self.championClass = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textMuted) }
                        .buttonStyle(.plain).help(tr("Clear filter"))
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
            }

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filtered, id: \.id) { champ in
                        Button { selection = champ.id } label: {
                            HStack(spacing: 10) {
                                ChampionIcon(id: champ.id, size: 30, ring: selection == champ.id ? Theme.accent : nil)
                                Text(champ.name).font(.callout.weight(selection == champ.id ? .semibold : .regular))
                                    .foregroundStyle(selection == champ.id ? Theme.text : Theme.textSecondary)
                                Spacer()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(selection == champ.id ? Theme.accent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 12)
            }
        }
        .frame(width: 210)
        .background(Theme.sidebar.opacity(0.6))
    }

    private func detail(_ championId: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                HeroBanner(splashPath: model.gameData.details[championId]?.splashPath, height: 230) {
                    HStack(alignment: .bottom, spacing: 16) {
                        ChampionIcon(id: championId, size: 72, ring: Theme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.gameData.championName(championId)).font(.system(size: 36, weight: .bold)).foregroundStyle(Theme.text)
                            Text(model.gameData.details[championId]?.title?.capitalized ?? "").font(.title3).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 10) {
                            Segmented(options: QueueMode.allCases.map { ($0, $0.title) }, selection: $mode)
                            if mode == .ranked {
                                Segmented(options: [(Lane?.none, tr("Main"))] + Lane.allCases.map { (Lane?.some($0), $0.title) }, selection: $lane)
                            }
                        }
                    }
                }
                if loading { ProgressView().controlSize(.small).frame(maxWidth: .infinity) }
                if let error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning) }
                if let lane, let build, build.lane != lane {
                    Label(tr("Few games as %@, showing %@.", lane.title, build.lane?.title ?? tr("main role")), systemImage: "info.circle.fill")
                        .foregroundStyle(Theme.textSecondary)
                }
                BuildDetails(build: build, extraRunes: highElo + riotRunes, championId: championId)
                if let build {
                    Button {
                        Task {
                            guard let summonerId = model.me?.summonerId else { return }
                            let name = model.gameData.championName(championId)
                            await model.perform(tr("Item set for %@ saved", name)) {
                                try await ClientActions.importItemSet(build, championName: name, summonerId: summonerId, mapId: mode.mapId, client: $0)
                            }
                        }
                    } label: { Label(tr("Save item set to client"), systemImage: "bag.badge.plus") }
                    .buttonStyle(.primary)
                    .disabled(model.connection != .connected)
                }
            }
            .padding(24)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
    }

    private var filtered: [ChampionSummary] {
        var all = model.gameData.sortedChampions
        if let championClass { all = all.filter { ($0.roles ?? []).contains(championClass) } }
        guard !search.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private func load(_ championId: Int) async {
        loading = true
        error = nil
        _ = await model.gameData.detail(championId, client: model.client)
        do {
            build = try await BuildService.opggBuild(championId: championId, lane: lane, mode: mode)
        } catch is CancellationError {
            return
        } catch {
            build = nil
            self.error = error.localizedDescription
        }
        if mode == .ranked, let master = try? await BuildService.opggBuild(championId: championId, lane: lane, mode: mode, tier: .masterPlus) {
            highElo = Array(master.runes.prefix(2))
        } else {
            highElo = []
        }
        if let client = model.client {
            riotRunes = (try? await BuildService.riotRecommended(client: client, championId: championId, lane: lane ?? build?.availableLanes.first, mapId: mode.mapId)) ?? []
        }
        loading = false
    }
}

struct TierListView: View {
    @Environment(AppModel.self) private var model
    @State private var entries: [TierListEntry] = []
    @Binding var lane: Lane
    @State private var sort: Sort = .rank
    @State private var error: String?
    var onOpen: (Int) -> Void

    enum Sort: String, CaseIterable { case rank, winRate, pickRate, banRate }

    var body: some View {
        Screen(title: tr("Tier list"), subtitle: tr("op.gg · all regions · current patch · click to open the build")) {
            Segmented(options: Lane.allCases.map { ($0, $0.title) }, selection: $lane)
        } content: {
            if let error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning) }
            topPicks
            Panel(padding: 0) {
                VStack(spacing: 0) {
                    header
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                        Button { onOpen(entry.championId) } label: { row(entry, index) }.buttonStyle(.plain)
                    }
                }
            }
        }
        .task { do { entries = try await BuildService.tierList() } catch { self.error = error.localizedDescription } }
    }

    private var topPicks: some View {
        let best = entries.filter { $0.lane == lane && $0.pickRate > 0.01 }.sorted { $0.winRate > $1.winRate }.prefix(4)
        return HStack(spacing: 12) {
            ForEach(Array(best)) { entry in
                Button { onOpen(entry.championId) } label: {
                    HStack(spacing: 12) {
                        ChampionIcon(id: entry.championId, size: 46, ring: Theme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tr("HIGHEST WIN RATE")).font(.system(size: 8.5, weight: .semibold)).tracking(0.5).foregroundStyle(Theme.textMuted)
                            Text(model.gameData.championName(entry.championId)).font(.headline).foregroundStyle(Theme.text)
                            Text(percent(entry.winRate)).font(.callout.weight(.semibold)).foregroundStyle(Theme.win)
                        }
                        Spacer()
                    }
                    .padding(12).panelBackground()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            headerCell("#", .rank, width: 60)
            Text(tr("Champion")).eyebrow().frame(maxWidth: .infinity, alignment: .leading)
            Text(tr("Tier")).eyebrow().frame(width: 60, alignment: .leading)
            headerCell(tr("Win rate"), .winRate, width: 220)
            headerCell(tr("Pick rate"), .pickRate, width: 100)
            headerCell(tr("Ban rate"), .banRate, width: 100)
            Text(tr("Games")).eyebrow().frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Theme.raised.opacity(0.5))
    }

    private func headerCell(_ title: String, _ key: Sort, width: CGFloat) -> some View {
        Button { sort = key } label: {
            HStack(spacing: 3) {
                Text(title).eyebrow()
                if sort == key { Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.accentBright) }
            }
        }
        .buttonStyle(.plain)
        .frame(width: width, alignment: .leading)
    }

    private func row(_ entry: TierListEntry, _ index: Int) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Text("\(entry.rank)").font(.callout.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                if entry.rankChange != 0 {
                    Image(systemName: entry.rankChange > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.system(size: 7)).foregroundStyle(entry.rankChange > 0 ? Theme.win : Theme.loss)
                        .help(tr("Moved %d places since last patch", abs(entry.rankChange)))
                }
            }
            .frame(width: 60, alignment: .leading)
            HStack(spacing: 10) {
                ChampionIcon(id: entry.championId, size: 32)
                Text(model.gameData.championName(entry.championId)).font(.callout.weight(.medium)).foregroundStyle(Theme.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(tierName(entry.tier)).font(.callout.weight(.bold))
                .foregroundStyle(entry.tier <= 1 ? Theme.gold : entry.tier == 2 ? Theme.accentBright : Theme.textSecondary)
                .frame(width: 60, alignment: .leading)
            WinRateMeter(winRate: entry.winRate).frame(width: 190).padding(.trailing, 30)
            Text(percent(entry.pickRate)).font(.callout.monospacedDigit()).foregroundStyle(Theme.text).frame(width: 100, alignment: .leading)
            Text(percent(entry.banRate)).font(.callout.monospacedDigit()).foregroundStyle(Theme.textSecondary).frame(width: 100, alignment: .leading)
            Text(entry.play.formatted()).font(.callout.monospacedDigit()).foregroundStyle(Theme.textMuted).frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
        .background(index.isMultiple(of: 2) ? Color.clear : Theme.raised.opacity(0.25))
        .contentShape(Rectangle())
    }

    private var rows: [TierListEntry] {
        let filtered = entries.filter { $0.lane == lane && $0.pickRate > 0.003 }
        switch sort {
        case .rank: return filtered.sorted { $0.rank < $1.rank }
        case .winRate: return filtered.sorted { $0.winRate > $1.winRate }
        case .pickRate: return filtered.sorted { $0.pickRate > $1.pickRate }
        case .banRate: return filtered.sorted { $0.banRate > $1.banRate }
        }
    }
}

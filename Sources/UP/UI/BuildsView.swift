import SwiftUI

struct BuildsView: View {
    @Binding var selection: Int?
    @Binding var championClass: String?
    @State private var lane: Lane?
    @State private var mode: QueueMode = .ranked

    var body: some View {
        ZStack {
            ChampionBrowser(championClass: $championClass) { championId, lane in
                self.lane = lane
                selection = championId
            }
            .equatable()
            .opacity(selection == nil ? 1 : 0)
            .allowsHitTesting(selection == nil)
            .accessibilityHidden(selection != nil)
            if let championId = selection {
                BuildPage(championId: championId, lane: lane, mode: $mode) { selection = nil }
                    .id(championId)
            }
        }
        .onChange(of: selection) { _, championId in
            if championId == nil { lane = nil }
        }
    }
}

/// Searchable grid of every champion, filterable by lane, under the player's own champions.
private struct ChampionBrowser: View, Equatable {
    @Environment(AppModel.self) private var model
    @Binding var championClass: String?
    var open: (Int, Lane?) -> Void
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    @State private var laneFilter: Lane?
    @State private var tierList: [TierListEntry] = []

    private static let columns = [GridItem(.adaptive(minimum: 88), spacing: 6)]

    /// The class filter is read through its binding and opening a build always does the same.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { true }

    var body: some View {
        Screen(title: tr("Builds & runes"), subtitle: tr("Runes, items, skill order, matchups and win rate by game length from op.gg, plus Riot's recommendations.")) {
            filterBar
            Group {
                if search.isEmpty, laneFilter == nil, championClass == nil { yourChampions }
                championGrid
            }
            .animation(nil, value: laneFilter)
        }
        .task {
            while tierList.isEmpty, !Task.isCancelled {
                if let entries = try? await BuildService.tierList(), !entries.isEmpty { tierList = entries } else { try? await Task.sleep(for: .seconds(20)) }
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(searchFocused ? Theme.accentBright : Theme.textMuted)
                TextField(tr("Search champion"), text: $search)
                    .textFieldStyle(.plain).foregroundStyle(Theme.text)
                    .focused($searchFocused)
                    .onSubmit { if let first = champions.first { pick(first.id, laneFilter) } }
                    .onExitCommand { search = "" }
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textMuted) }
                        .buttonStyle(.plain).handCursor()
                }
            }
            .padding(.horizontal, 12)
            .frame(width: 320, height: 36)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(searchFocused ? Theme.accent : Theme.hairline))
            Segmented(options: [(Lane?.none, tr("All"))] + Lane.allCases.map { (Lane?.some($0), $0.title) }, selection: $laneFilter)
                .disabled(tierList.isEmpty)
                .opacity(tierList.isEmpty ? 0.5 : 1)
            if let championClass {
                Chip(text: "#\(championClass)", tone: .accent, symbol: "number")
                Button { self.championClass = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textMuted) }
                    .buttonStyle(.plain).handCursor().help(tr("Clear filter"))
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var yourChampions: some View {
        let ids = favourites
        if !ids.isEmpty {
            let tiers = self.tiers
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("Your champions")).eyebrow()
                HStack(spacing: 12) {
                    ForEach(ids, id: \.self) { id in
                        ChampionCard(id: id, detail: favouriteDetail(id), tier: tiers[id]) { pick(id, nil) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .task(id: ids) { await model.gameData.prefetchDetails(ids, client: model.client) }
        } else if model.myProfile == nil {
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("Your champions")).eyebrow()
                HStack(spacing: 12) {
                    ForEach(0..<6, id: \.self) { _ in Bone(height: 132, radius: 12).frame(maxWidth: 220) }
                }
                .shimmering()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .environment(\.shimmers, model.connection == .connected)
        }
    }

    @ViewBuilder
    private var championGrid: some View {
        let shown = champions
        let tiers = self.tiers
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(tr("Champions")).eyebrow()
                if !model.gameData.sortedChampions.isEmpty {
                    Text("\(shown.count)").font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.textMuted)
                }
            }
            if model.gameData.sortedChampions.isEmpty {
                LazyVGrid(columns: Self.columns, spacing: 6) {
                    ForEach(0..<36, id: \.self) { index in
                        VStack(spacing: 7) {
                            Bone(width: 60, height: 60, radius: 14.4)
                            Bone(width: [52, 38, 60, 44, 56, 40][index % 6], height: 8, line: 15)
                        }
                        .shimmering()
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                }
                .environment(\.shimmers, model.connection == .connected)
            } else if shown.isEmpty {
                Text(tr("No champions found.")).font(.callout).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 32)
            } else {
                LazyVGrid(columns: Self.columns, spacing: 6) {
                    ForEach(shown, id: \.id) { champion in
                        ChampionTile(id: champion.id, name: champion.name, tier: tiers[champion.id]) { pick(champion.id, laneFilter) }
                            .equatable()
                    }
                }
            }
        }
    }

    private var champions: [ChampionSummary] {
        var all = model.gameData.sortedChampions
        if let championClass { all = all.filter { ($0.roles ?? []).contains(championClass) } }
        if let laneFilter {
            let inLane = Set(tierList.filter { $0.lane == laneFilter }.map(\.championId))
            all = all.filter { inLane.contains($0.id) }
        }
        guard !search.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    /// Tier of each champion in the picked lane, or in its most played lane when no lane is picked.
    private var tiers: [Int: Int] {
        Dictionary(grouping: tierList.filter { laneFilter == nil || $0.lane == laneFilter }, by: \.championId)
            .compactMapValues { $0.max { $0.play < $1.play }?.tier }
    }

    /// The signed-in player's most played recent champions, latest first among equals, then their highest mastery ones.
    private var favourites: [Int] {
        let recent = model.myProfile?.recent.compactMap { $0.me?.championId } ?? []
        let played = (model.myProfile?.champions ?? []).sorted {
            $0.games != $1.games ? $0.games > $1.games : (recent.firstIndex(of: $0.championId) ?? 0) < (recent.firstIndex(of: $1.championId) ?? 0)
        }
        var seen = Set<Int>()
        let ids = played.map(\.championId) + model.myMasteries.map(\.championId)
        return Array(ids.filter { model.gameData.champions[$0] != nil && seen.insert($0).inserted }.prefix(6))
    }

    private func favouriteDetail(_ championId: Int) -> String {
        if let profile = model.myProfile, let record = profile.champions.first(where: { $0.championId == championId }) {
            return profile.usesPracticeGames ? gamesLabel(record.games) : "\(gamesLabel(record.games)) · \(percent(record.winRate, digits: 0))"
        }
        return tr("Mastery %@", compact(Double(model.myMasteries.first { $0.championId == championId }?.championPoints ?? 0)))
    }

    /// Opens a build without leaving the hidden search field focused.
    private func pick(_ championId: Int, _ lane: Lane?) {
        searchFocused = false
        open(championId, lane)
    }
}

/// One champion's build with its queue and lane pickers, under a link back to the champion grid.
private struct BuildPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.contentBottomInset) private var bottomInset
    let championId: Int
    @State private var lane: Lane?
    @Binding var mode: QueueMode
    var back: () -> Void
    @State private var build: ChampionBuild?
    @State private var riotRunes: [RuneSetup] = []
    @State private var highElo: [RuneSetup] = []
    @State private var loading = true
    @State private var error: String?

    init(championId: Int, lane: Lane?, mode: Binding<QueueMode>, back: @escaping () -> Void) {
        self.championId = championId
        _lane = State(initialValue: lane)
        _mode = mode
        self.back = back
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                Button(action: back) {
                    Label(tr("Champions"), systemImage: "chevron.left").font(.callout.weight(.semibold)).foregroundStyle(Theme.accentBright)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).handCursor()
                .padding(.bottom, -8)
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
                if let error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning) }
                if mode == .ranked, let lane, let build, build.lane != lane {
                    Label(tr("Few games as %@, showing %@.", lane.title, build.lane?.title ?? tr("main role")), systemImage: "info.circle.fill")
                        .foregroundStyle(Theme.textSecondary)
                }
                if loading, build == nil {
                    LoadingNote(text: tr("Loading the %@ build from op.gg…", model.gameData.championName(championId)))
                    BuildSkeleton()
                } else {
                    BuildDetails(build: build, extraRunes: highElo + riotRunes, championId: championId, showRunes: mode != .arena)
                }
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
            .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 24 + bottomInset)
            .frame(maxWidth: 1280)
            .frame(maxWidth: .infinity)
        }
        .task(id: "\(lane?.rawValue ?? "")-\(mode.rawValue)") { await load() }
    }

    private func load() async {
        loading = true
        error = nil
        build = nil
        highElo = []
        riotRunes = []
        let lane = self.lane, mode = self.mode, client = model.client
        async let detail = model.gameData.detail(championId, client: client)
        async let master = mode == .ranked ? try? BuildService.opggBuild(championId: championId, lane: lane, mode: mode, tier: .masterPlus) : nil
        var loaded: ChampionBuild?
        var failure: String?
        do {
            loaded = try await BuildService.opggBuild(championId: championId, lane: lane, mode: mode)
        } catch {
            failure = error.localizedDescription
        }
        var riot: [RuneSetup] = []
        if mode == .arena {
            await model.gameData.loadAugments(client: client)
        } else if let client {
            riot = (try? await BuildService.riotRecommended(client: client, championId: championId, lane: lane ?? loaded?.availableLanes.first, mapId: mode.mapId)) ?? []
        }
        let elite = Array((await master)?.runes.prefix(2) ?? [])
        _ = await detail
        guard !Task.isCancelled else { return }
        build = loaded
        highElo = elite
        riotRunes = riot
        error = failure
        loading = false
    }
}

/// Splash-art card that opens the build of one of the player's own champions.
private struct ChampionCard: View {
    @Environment(AppModel.self) private var model
    let id: Int
    let detail: String
    let tier: Int?
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Color.clear
                .overlay {
                    LCUImage(path: model.gameData.details[id]?.tilePath, size: nil, corner: 0, fill: Theme.surface, contentMode: .fill)
                        .scaleEffect(hovered ? 1.06 : 1)
                }
                .overlay {
                    LinearGradient(colors: [Theme.background.opacity(0), Theme.background.opacity(0.92)], startPoint: .center, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.gameData.championName(id)).font(.headline).foregroundStyle(Theme.text)
                        Text(detail).font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    .lineLimit(1)
                    .padding(12)
                }
                .overlay(alignment: .topTrailing) {
                    if let tier { TierBadge(tier: tier).padding(8) }
                }
                .frame(maxWidth: 220)
                .frame(height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(hovered ? Theme.accent : Theme.hairline, lineWidth: hovered ? 1.5 : 1))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain).handCursor()
        .onHover { inside in withAnimation(.snappy(duration: 0.2)) { hovered = inside } }
    }
}

/// Portrait and name that open a champion's build, with the champion's tier.
private struct ChampionTile: View, Equatable {
    let id: Int
    let name: String
    let tier: Int?
    let action: () -> Void
    @State private var hovered = false

    /// The action reads the current lane filter when tapped, so only what the tile shows matters.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && lhs.name == rhs.name && lhs.tier == rhs.tier }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    ChampionIcon(id: id, size: 60, ring: hovered ? Theme.accent : nil)
                    if let tier { TierBadge(tier: tier).offset(x: 5, y: -5) }
                }
                .scaleEffect(hovered ? 1.06 : 1)
                Text(name).font(.caption.weight(.medium)).foregroundStyle(hovered ? Theme.text : Theme.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10).padding(.horizontal, 4)
            .background {
                if hovered { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface) }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain).handCursor()
        .onHover { inside in withAnimation(.snappy(duration: 0.15)) { hovered = inside } }
    }
}

/// op.gg tier letter in a small capsule, gold for OP and S, blue for A.
private struct TierBadge: View {
    let tier: Int

    var body: some View {
        let color = tier <= 1 ? Theme.gold : tier == 2 ? Theme.accentBright : Theme.textSecondary
        Text(tierName(tier)).font(.system(size: 9, weight: .heavy)).foregroundStyle(color)
            .padding(.horizontal, 4).frame(minWidth: 17, minHeight: 15)
            .background(Capsule().fill(Theme.background).stroke(color.opacity(0.55)))
    }
}

struct TierListView: View, Equatable {
    @Environment(AppModel.self) private var model
    @State private var entries: [TierListEntry] = []
    @Binding var lane: Lane
    @State private var sort: Sort = .rank
    @State private var error: String?
    @State private var shown = 20
    var onOpen: (Int) -> Void

    /// The lane is read through its binding and opening a build always does the same.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { true }

    enum Sort: String, CaseIterable { case rank, winRate, pickRate, banRate }

    var body: some View {
        Screen(title: tr("Tier list"), subtitle: tr("op.gg · all regions · current patch · click to open the build")) {
            Segmented(options: Lane.allCases.map { ($0, $0.title) }, selection: $lane)
        } content: {
            if let error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning) }
            if entries.isEmpty, error == nil {
                TierListSkeleton(header: header)
            } else {
                let rows = self.rows
                topPicks
                Panel(padding: 0) {
                    LazyVStack(spacing: 0) {
                        header
                        ForEach(Array(rows.prefix(shown).enumerated()), id: \.element.id) { index, entry in
                            Button { onOpen(entry.championId) } label: { row(entry, index) }.buttonStyle(.plain).handCursor()
                        }
                    }
                }
                if rows.count > shown {
                    Button { shown += 20 } label: { Label(tr("Show more"), systemImage: "chevron.down") }
                        .buttonStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
        }
        .task { do { entries = try await BuildService.tierList() } catch { self.error = error.localizedDescription } }
        .onChange(of: lane) { shown = 20 }
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
                .buttonStyle(.plain).handCursor()
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
        .buttonStyle(.plain).handCursor()
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

/// Placeholder for the top picks and the table while the tier list loads.
private struct TierListSkeleton<Header: View>: View {
    let header: Header

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 12) {
                    Bone(width: 46, height: 46, radius: 11)
                    VStack(alignment: .leading, spacing: 5) {
                        Bone(width: 92, height: 6, line: 10)
                        Bone(width: 72, height: 11, line: 17)
                        Bone(width: 42, height: 9, line: 15)
                    }
                    Spacer()
                }
                .shimmering()
                .padding(12).panelBackground()
            }
        }
        Panel(padding: 0) {
            VStack(spacing: 0) {
                header
                ForEach(0..<12, id: \.self) { index in
                    HStack(spacing: 0) {
                        Bone(width: 16, height: 9).frame(width: 60, alignment: .leading)
                        HStack(spacing: 10) {
                            Bone(width: 32, height: 32, radius: 8)
                            Bone(width: [86, 64, 102, 74, 92, 58][index % 6], height: 9)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Bone(width: 18, height: 10).frame(width: 60, alignment: .leading)
                        VStack(alignment: .leading, spacing: 7) {
                            Bone(width: 44, height: 9)
                            Bone(width: 190, height: 6, radius: 3)
                        }
                        .frame(width: 190, alignment: .leading).padding(.trailing, 30)
                        Bone(width: 40, height: 9).frame(width: 100, alignment: .leading)
                        Bone(width: 36, height: 9).frame(width: 100, alignment: .leading)
                        Bone(width: 52, height: 9).frame(width: 90, alignment: .trailing)
                    }
                    .shimmering()
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(index.isMultiple(of: 2) ? Color.clear : Theme.raised.opacity(0.25))
                }
            }
        }
    }
}

import Foundation

/// Hashtag shortcuts offered by the search bar.
enum SearchTag: String, CaseIterable, Identifiable {
    case top, jungle, mid, adc, support
    case assassins, fighters, mages, marksmen, tanks, supports
    case tierlist, builds, history, tools, overview, me, settings, preview, hud

    var id: String { rawValue }
    var label: String { "#\(rawValue)" }

    var lane: Lane? {
        switch self {
        case .top: .top
        case .jungle: .jungle
        case .mid: .middle
        case .adc: .bottom
        case .support: .utility
        default: nil
        }
    }

    /// Champion class as used in the client's champion roles.
    var championClass: String? {
        switch self {
        case .assassins: "assassin"
        case .fighters: "fighter"
        case .mages: "mage"
        case .marksmen: "marksman"
        case .tanks: "tank"
        case .supports: "support"
        default: nil
        }
    }

    var summary: String {
        if let lane { return tr("Tier list for %@", lane.title) }
        switch self {
        case .assassins: return tr("Assassin champions")
        case .fighters: return tr("Fighter champions")
        case .mages: return tr("Mage champions")
        case .marksmen: return tr("Marksman champions")
        case .tanks: return tr("Tank champions")
        case .supports: return tr("Support champions")
        case .tierlist: return tr("Open the tier list")
        case .builds: return tr("Open builds & runes")
        case .history: return tr("Open your match history")
        case .tools: return tr("Open tools")
        case .overview: return tr("Open the overview")
        case .me: return tr("Your own profile")
        case .settings: return tr("Open settings")
        case .preview: return tr("Preview champ select")
        case .hud: return tr("Preview the in-game HUD")
        default: return ""
        }
    }

    var symbol: String {
        if let lane { return lane.symbol }
        switch self {
        case .assassins, .fighters, .mages, .marksmen, .tanks, .supports: return "person.3.fill"
        case .tierlist: return "chart.bar.fill"
        case .builds: return "books.vertical.fill"
        case .history: return "clock.arrow.circlepath"
        case .tools: return "wrench.and.screwdriver.fill"
        case .overview: return "square.grid.2x2.fill"
        case .me: return "person.crop.circle"
        case .settings: return "gearshape.fill"
        case .preview: return "binoculars.fill"
        case .hud: return "rectangle.on.rectangle"
        default: return "number"
        }
    }
}

struct SearchSuggestion: Identifiable, Hashable {
    enum Kind: Hashable {
        case champion(Int)
        case player(PlayerQuery)
        case account(PlayerQuery)
        case tag(SearchTag)
    }

    var kind: Kind
    var title: String
    var subtitle: String
    var symbol: String
    var championId: Int?
    var iconId: Int?
    var imageURL: String?
    var tier: String?
    var rank: String?
    var pro: String?

    var id: String {
        switch kind {
        case let .champion(id): "c\(id)"
        case let .player(query): "p\(query.stored.lowercased())"
        case let .account(query): "a\(query.stored.lowercased())"
        case let .tag(tag): "t\(tag.rawValue)"
        }
    }

    var section: String {
        switch kind {
        case .champion: tr("Champions")
        case .player: tr("Players")
        case let .account(query): tr("Accounts on %@", query.region.code)
        case .tag: tr("Tags")
        }
    }

    /// Account suggestion for a player op.gg found on the server.
    init(account hit: AccountHit, region: Region) {
        self.init(kind: .account(PlayerQuery(riotId: hit.riotId, region: region)), title: hit.riotId,
                  subtitle: hit.level.map { tr("Level %d", $0) } ?? "", symbol: "person.crop.circle",
                  imageURL: hit.iconURL, tier: hit.tier, rank: hit.rank ?? tr("Unranked"), pro: hit.pro)
    }

    init(kind: Kind, title: String, subtitle: String, symbol: String, championId: Int? = nil, iconId: Int? = nil,
         imageURL: String? = nil, tier: String? = nil, rank: String? = nil, pro: String? = nil) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.championId = championId
        self.iconId = iconId
        self.imageURL = imageURL
        self.tier = tier
        self.rank = rank
        self.pro = pro
    }
}

enum SearchEngine {
    /// Champion and known-player suggestions (shown above server accounts) and tag suggestions (shown below them).
    @MainActor
    static func suggestions(for raw: String, model: AppModel) -> (leading: [SearchSuggestion], tags: [SearchSuggestion]) {
        let query = raw.trimmingCharacters(in: .whitespaces)
        let lowered = query.lowercased()
        if query.isEmpty { return (recent(model), Array(tags(matching: "").prefix(6))) }
        if lowered.hasPrefix("#") { return ([], Array(tags(matching: String(lowered.dropFirst())).prefix(10))) }
        return (Array(champions(lowered, model).prefix(5)) + Array(players(query, model).prefix(5)), Array(tags(matching: lowered).prefix(3)))
    }

    /// Name to look up on the server for a query, or nil when it is too short or only a tag.
    static func accountName(_ raw: String) -> String? {
        let query = raw.trimmingCharacters(in: .whitespaces)
        guard !query.hasPrefix("#") else { return nil }
        let parts = query.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        if parts.count == 2 { return parts[1].count >= 2 ? query : nil }
        return query.count >= 2 ? query : nil
    }

    private static func looksLikeRiotId(_ query: String) -> Bool {
        guard let hash = query.firstIndex(of: "#") else { return false }
        return hash != query.startIndex && query[query.index(after: hash)...].count >= 2
    }

    private static func score(_ text: String, _ query: String) -> Int? {
        let text = text.lowercased()
        if text == query { return 0 }
        if text.hasPrefix(query) { return 1 }
        if text.split(separator: " ").contains(where: { $0.hasPrefix(query) }) { return 2 }
        if text.contains(query) { return 3 }
        return nil
    }

    @MainActor
    private static func champions(_ query: String, _ model: AppModel) -> [SearchSuggestion] {
        let letters = query.filter { $0.isLetter || $0 == " " }
        guard !letters.isEmpty else { return [] }
        return model.gameData.sortedChampions
            .compactMap { champ -> (Int, ChampionSummary)? in
                let best = [score(champ.name, letters), score(champ.alias, letters)].compactMap { $0 }.min()
                return best.map { ($0, champ) }
            }
            .sorted { $0.0 == $1.0 ? $0.1.name < $1.1.name : $0.0 < $1.0 }
            .map { _, champ in
                SearchSuggestion(kind: .champion(champ.id), title: champ.name,
                                 subtitle: (champ.roles ?? []).map(\.capitalized).joined(separator: " · "),
                                 symbol: "person.fill", championId: champ.id)
            }
    }

    @MainActor
    private static func players(_ query: String, _ model: AppModel) -> [SearchSuggestion] {
        let lowered = query.lowercased()
        let home = model.clientRegion ?? model.searchRegion
        var known: [(query: PlayerQuery, subtitle: String, icon: Int?)] = []
        if let me = model.myQuery { known.append((me, tr("You"), model.me?.profileIconId)) }
        known += model.friends.compactMap { f in f.riotId.map { (PlayerQuery(riotId: $0, region: home), tr("Friend"), f.icon) } }
        known += model.recentPlayers.map { ($0, $0.region == home ? tr("Recent search") : tr("Recent search · %@", $0.region.code), nil) }
        known += model.teamProfiles.values.compactMap { p in
            p.summoner.map { (PlayerQuery(riotId: $0.riotId, region: home), tr("Recent teammate"), $0.profileIconId) }
        }
        var seen = Set<String>()
        var result: [SearchSuggestion] = []
        if looksLikeRiotId(query) {
            let lookup = PlayerQuery(riotId: query, region: model.searchRegion)
            seen.insert(lookup.stored.lowercased())
            result.append(SearchSuggestion(kind: .player(lookup), title: query, subtitle: tr("Look up this Riot ID on %@", lookup.region.code), symbol: "magnifyingglass"))
        }
        let ranked = known.compactMap { entry -> (Int, (query: PlayerQuery, subtitle: String, icon: Int?))? in
            score(entry.query.riotId, lowered).map { ($0, entry) }
        }.sorted { $0.0 < $1.0 }
        for (_, entry) in ranked where seen.insert(entry.query.stored.lowercased()).inserted {
            result.append(SearchSuggestion(kind: .player(entry.query), title: entry.query.riotId, subtitle: entry.subtitle,
                                           symbol: "person.crop.circle", iconId: entry.icon))
        }
        return result
    }

    private static func tags(matching query: String) -> [SearchSuggestion] {
        SearchTag.allCases.compactMap { tag -> (Int, SearchTag)? in
            if query.isEmpty { return (0, tag) }
            let summaryScore = query.count >= 3 ? score(tag.summary, query).map { $0 + 4 } : nil
            let best = [score(tag.rawValue, query), summaryScore].compactMap { $0 }.min()
            return best.map { ($0, tag) }
        }
        .sorted { $0.0 < $1.0 }
        .map { SearchSuggestion(kind: .tag($0.1), title: $0.1.label, subtitle: $0.1.summary, symbol: $0.1.symbol) }
    }

    @MainActor
    private static func recent(_ model: AppModel) -> [SearchSuggestion] {
        let home = model.clientRegion ?? model.searchRegion
        return model.recentPlayers.prefix(4).map {
            SearchSuggestion(kind: .player($0), title: $0.riotId,
                             subtitle: $0.region == home ? tr("Recent search") : tr("Recent search · %@", $0.region.code), symbol: "clock.arrow.circlepath")
        }
    }
}

import Foundation

/// Profile, friends-list card, friend request, loot, lobby, champ select and account actions offered by the client's local API.
enum ClientTools {
    struct Icon: Decodable, Sendable, Identifiable, Hashable {
        var id: Int
        var title: String?
    }

    struct Queue: Decodable, Sendable, Identifiable, Hashable {
        struct GameType: Decodable, Sendable, Hashable { var id: Int? }
        var id: Int
        var name: String?
        var description: String?
        var gameMode: String?
        var mapId: Int?
        var category: String?
        var isCustom: Bool?
        var queueAvailability: String?
        var numPlayersPerTeam: Int?
        var gameTypeConfig: GameType?

        var title: String {
            let name = (name ?? "").trimmingCharacters(in: .whitespaces)
            let description = (description ?? "").trimmingCharacters(in: .whitespaces)
            if name.isEmpty { return description.isEmpty ? "#\(id)" : description }
            return description.isEmpty || description == name ? name : "\(name) · \(description)"
        }
    }

    struct LootItem: Decodable, Sendable {
        var lootId: String
        var type: String?
        var count: Int?
        var disenchantValue: Int?
        var redeemableStatus: String?
    }

    struct Champion: Decodable, Sendable, Identifiable {
        struct Ownership: Decodable, Sendable { var owned: Bool? }
        struct Skin: Decodable, Sendable { var id: Int; var ownership: Ownership? }
        var id: Int
        var name: String
        var purchased: Double?
        var ownership: Ownership?
        var skins: [Skin]?

        var purchaseDate: Date? { purchased.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil } }
    }

    struct RerollPoints: Decodable, Sendable {
        var currentPoints: Int?
        var maxRolls: Int?
        var numberOfRolls: Int?
        var pointsCostToRoll: Int?
    }

    struct Progress: Decodable, Sendable {
        var summonerLevel: Int?
        var xpSinceLastLevel: Int?
        var xpUntilNextLevel: Int?
        var rerollPoints: RerollPoints?
    }

    struct Honor: Decodable, Sendable {
        var honorLevel: Int?
    }

    enum Tokens { case none, glitched, firstThreeTimes }

    enum ToolError: LocalizedError {
        case noTokens, noRecipe, noChampion, badBackup

        var errorDescription: String? {
            switch self {
            case .noTokens: tr("You have no challenge token selected.")
            case .noRecipe: tr("The client offers no recipe for this.")
            case .noChampion: tr("You have no champion to keep yet.")
            case .badBackup: tr("This file is not a UP! settings backup.")
            }
        }
    }

    private struct InventoryIcon: Decodable { var itemId: Int }
    private struct FriendRequest: Decodable { var puuid: String; var direction: String? }
    private struct Recipe: Decodable { var recipeName: String }
    private struct Bot: Decodable { var id: Int }

    /// Every icon in the game, newest first.
    static func allIcons(client: LCUClient) async throws -> [Icon] {
        try await client.get("/lol-game-data/assets/v1/summoner-icons.json", as: [Icon].self).sorted { $0.id > $1.id }
    }

    /// Icons the player owns and can wear on the profile, newest first.
    static func ownedIcons(client: LCUClient) async throws -> [Icon] {
        async let all = allIcons(client: client)
        let owned = Set(try await client.get("/lol-inventory/v2/inventory/SUMMONER_ICON", as: [InventoryIcon].self).map(\.itemId))
        return try await all.filter { owned.contains($0.id) }
    }

    static func setProfileIcon(_ id: Int, client: LCUClient) async throws {
        try await client.put("/lol-summoner/v1/current-summoner/icon", ["profileIconId": id])
    }

    /// Icon friends see next to the player in their friends list.
    static func setChatIcon(_ id: Int, client: LCUClient) async throws {
        try await client.put("/lol-chat/v1/me", ["icon": id])
    }

    static func setBackground(skinId: Int, client: LCUClient) async throws {
        try await client.post("/lol-summoner/v1/current-summoner/summoner-profile", ["key": "backgroundSkinId", "value": skinId])
    }

    /// Overrides values on the card friends see when hovering the player, such as the rank or mastery score.
    static func setCard(_ values: [String: String], client: LCUClient) async throws {
        try await client.put("/lol-chat/v1/me", ["lol": values])
    }

    /// Changes the challenge tokens shown on the profile and the friends-list card.
    static func setTokens(_ tokens: Tokens, client: LCUClient) async throws {
        try await updatePreferences(client: client) { preferences, current in
            switch tokens {
            case .none:
                preferences["challengeIds"] = [Int]()
            case .glitched:
                preferences["challengeIds"] = [0, 0, 0]
            case .firstThreeTimes:
                guard let first = current.first else { throw ToolError.noTokens }
                preferences["challengeIds"] = [first, first, first]
            }
        }
    }

    /// Shows last season's banner, which leaves no banner at all for players who were unranked then.
    static func showLastSeasonBanner(client: LCUClient) async throws {
        try await updatePreferences(client: client) { preferences, _ in preferences["bannerAccent"] = "2" }
    }

    /// Posts the challenge preferences with one change, keeping the tokens, title and banner already chosen.
    private static func updatePreferences(client: LCUClient, _ change: (inout [String: Any], [Int]) throws -> Void) async throws {
        let summary = try JSONSerialization.jsonObject(with: try await client.request("GET", "/lol-challenges/v1/summary-player-data/local-player")) as? [String: Any] ?? [:]
        let current = (summary["topChallenges"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? Int }
        var preferences: [String: Any] = ["challengeIds": current]
        if let title = (summary["title"] as? [String: Any])?["itemId"] as? Int, title != -1 { preferences["title"] = String(title) }
        if let banner = summary["bannerId"] as? String, !banner.isEmpty { preferences["bannerAccent"] = banner }
        try change(&preferences, current)
        try await client.post("/lol-challenges/v1/update-player-preferences/", preferences)
    }

    static func incomingFriendRequests(client: LCUClient) async throws -> Int {
        try await client.get("/lol-chat/v2/friend-requests", as: [FriendRequest].self).filter { $0.direction == "in" }.count
    }

    /// Accepts or declines every incoming friend request and returns how many were answered.
    static func answerFriendRequests(accept: Bool, client: LCUClient) async throws -> Int {
        let requests = try await client.get("/lol-chat/v2/friend-requests", as: [FriendRequest].self).filter { $0.direction == "in" }
        for request in requests {
            if accept {
                try await client.put("/lol-chat/v2/friend-requests/\(request.puuid)", ["direction": "both"])
            } else {
                try await client.delete("/lol-chat/v2/friend-requests/\(request.puuid)")
            }
        }
        return requests.count
    }

    static func loot(client: LCUClient) async throws -> [LootItem] {
        try await client.get("/lol-loot/v1/player-loot", as: [LootItem].self)
    }

    /// Shards of champions the player already owns, which are only worth Blue Essence.
    static func ownedChampionShards(in loot: [LootItem]) -> [LootItem] {
        loot.filter { ($0.type == "CHAMPION_RENTAL" || $0.type == "CHAMPION") && $0.redeemableStatus == "ALREADY_OWNED" }
    }

    /// Skins, ward skins, icons and emotes the player already owns, which are only worth Orange Essence.
    static func ownedCosmeticShards(in loot: [LootItem]) -> [LootItem] {
        loot.filter { $0.redeemableStatus == "ALREADY_OWNED" && ($0.disenchantValue ?? 0) > 0 && !["CHAMPION_RENTAL", "CHAMPION"].contains($0.type ?? "") }
    }

    static func keyFragments(in loot: [LootItem]) -> Int {
        loot.first { $0.lootId == "MATERIAL_key_fragment" }?.count ?? 0
    }

    /// Balance of a loot currency such as `CURRENCY_champion` (Blue Essence) or `CURRENCY_cosmetic` (Orange Essence).
    static func currency(_ lootId: String, in loot: [LootItem]) -> Int {
        loot.first { $0.lootId == lootId }?.count ?? 0
    }

    static func riotPoints(client: LCUClient) async throws -> Int {
        (try JSONSerialization.jsonObject(with: try await client.request("GET", "/lol-inventory/v1/wallet/RP")) as? [String: Any])?["RP"] as? Int ?? 0
    }

    static func disenchant(_ items: [LootItem], client: LCUClient) async throws {
        for item in items {
            try await client.post("/lol-loot/v1/recipes/\(item.type ?? "CHAMPION_RENTAL")_disenchant/craft?repeat=\(max(item.count ?? 1, 1))", [item.lootId])
        }
    }

    /// Forges as many keys as the fragments allow, three fragments each.
    static func craftKeys(fragments: Int, client: LCUClient) async throws {
        let recipes = try await client.get("/lol-loot/v1/recipes/initial-item/MATERIAL_key_fragment", as: [Recipe].self)
        guard let recipe = recipes.first(where: { $0.recipeName.localizedCaseInsensitiveContains("forge") }) ?? recipes.first else { throw ToolError.noRecipe }
        try await client.post("/lol-loot/v1/recipes/\(recipe.recipeName)/craft?repeat=\(fragments / 3)", ["MATERIAL_key_fragment"])
    }

    /// Queues the server currently accepts, custom games included.
    static func queues(client: LCUClient) async throws -> [Queue] {
        try await client.get("/lol-game-queues/v1/queues", as: [Queue].self).filter { $0.queueAvailability == "Available" }.sorted { $0.id < $1.id }
    }

    /// Opens a lobby for the queue; a custom queue gets a custom game lobby with the given name and pick mode.
    static func createLobby(_ queue: Queue, name: String, pickMode: Int? = nil, client: LCUClient) async throws {
        guard queue.isCustom == true else { return try await client.post("/lol-lobby/v2/lobby", ["queueId": queue.id]) }
        try await client.post("/lol-lobby/v2/lobby", [
            "customGameLobby": [
                "configuration": [
                    "gameMode": queue.gameMode ?? "CLASSIC", "mapId": queue.mapId ?? 11, "mutators": ["id": pickMode ?? queue.gameTypeConfig?.id ?? 1],
                    "spectatorPolicy": "AllAllowed", "teamSize": max(queue.numPlayersPerTeam ?? 5, 1),
                ],
                "lobbyName": name, "lobbyPassword": "",
            ],
            "isCustom": true,
        ])
    }

    /// Fills a team of a custom lobby (`100` yours, `200` the enemy) with random bots and returns how many joined.
    static func addBots(difficulty: String, team: String, client: LCUClient) async throws -> Int {
        let bots = try await client.get("/lol-lobby/v2/lobby/custom/available-bots", as: [Bot].self).shuffled()
        var added = 0
        for bot in bots.prefix(5) {
            do {
                try await client.post("/lol-lobby/v1/lobby/custom/bots", ["championId": bot.id, "botDifficulty": difficulty, "teamId": team])
                added += 1
            } catch {
                if added == 0 { throw error }
                break
            }
        }
        return added
    }

    /// Leaves champion select without closing the client; the usual dodge penalty still applies.
    static func dodge(client: LCUClient) async throws {
        let args = #"["","teambuilder-draft","quitV2",""]"#
        let query = args.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? args
        try await client.post("/lol-login/v1/session/invoke?destination=lcdsServiceProxy&method=call&args=\(query)", ["data": ["", "teambuilder-draft", "quitV2", ""]])
    }

    /// Rerolls the ARAM champion, then takes the previous one back from the bench so the new roll is left to the team.
    static func rerollForTeam(client: LCUClient) async throws {
        let current = try await client.get("/lol-champ-select/v1/current-champion", as: Int.self)
        guard current > 0 else { throw ToolError.noChampion }
        try await client.post("/lol-champ-select/v1/session/my-selection/reroll")
        for attempt in 1...10 {
            do {
                return try await client.post("/lol-champ-select/v1/session/bench/swap/\(current)")
            } catch where attempt < 10 {
                try await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Level, experience and ARAM reroll points of the signed-in player.
    static func progress(client: LCUClient) async throws -> Progress {
        try await client.get("/lol-summoner/v1/current-summoner", as: Progress.self)
    }

    static func honor(client: LCUClient) async throws -> Honor {
        try await client.get("/lol-honor-v2/v1/profile", as: Honor.self)
    }

    /// In-game settings and hotkeys as one JSON document.
    static func gameSettings(client: LCUClient) async throws -> Data {
        async let game = client.request("GET", "/lol-game-settings/v1/game-settings")
        async let input = client.request("GET", "/lol-game-settings/v1/input-settings")
        let backup: [String: Any] = [
            "gameSettings": try JSONSerialization.jsonObject(with: try await game),
            "inputSettings": try JSONSerialization.jsonObject(with: try await input),
        ]
        return try JSONSerialization.data(withJSONObject: backup, options: [.prettyPrinted, .sortedKeys])
    }

    /// Applies settings and hotkeys saved by `gameSettings(client:)`.
    static func restoreGameSettings(_ data: Data, client: LCUClient) async throws {
        guard let backup = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let game = backup["gameSettings"] as? [String: Any], let input = backup["inputSettings"] as? [String: Any] else { throw ToolError.badBackup }
        try await client.patch("/lol-game-settings/v1/game-settings", game)
        try await client.patch("/lol-game-settings/v1/input-settings", input)
        try? await client.post("/lol-game-settings/v1/save")
    }

    /// Owned champions with their purchase dates, oldest first.
    static func collection(summonerId: Int, client: LCUClient) async throws -> [Champion] {
        try await client.get("/lol-champions/v1/inventories/\(summonerId)/champions", as: [Champion].self)
            .filter { $0.ownership?.owned == true }
            .sorted { ($0.purchased ?? .infinity) < ($1.purchased ?? .infinity) }
    }

    /// Shows a notification with any text in the League client.
    static func notification(title: String, text: String, client: LCUClient) async throws {
        try await client.post("/player-notifications/v1/notifications", [
            "critical": false, "dismissible": true, "state": "toast", "type": "default", "source": "UP!",
            "titleKey": "pre_translated_title", "detailKey": "pre_translated_details",
            "data": ["title": title, "details": text], "iconUrl": "", "backgroundUrl": "",
        ])
    }
}

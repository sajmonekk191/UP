import Foundation

/// Writes runes, summoner spells and item sets into the League client.
enum ClientActions {
    static let pagePrefix = "UP!"

    /// Accepts a found match through the service running the queue: classic matchmaking, else team builder.
    static func acceptMatch(client: LCUClient) async throws {
        do {
            try await client.post("/lol-matchmaking/v1/ready-check/accept")
        } catch {
            try await client.post("/lol-lobby-team-builder/v1/ready-check/accept")
        }
    }

    /// Replaces the toolkit's own rune page (or the current page when no slot is free) with the setup.
    static func importRunes(_ setup: RuneSetup, championName: String, client: LCUClient, allowOverwrite: Bool) async throws {
        let pages: [PerkPage] = try await client.get("/lol-perks/v1/pages")
        for page in pages where page.name.hasPrefix(pagePrefix) && page.isDeletable == true {
            try await client.delete("/lol-perks/v1/pages/\(page.id)")
        }

        let inventory: PerkInventory = try await client.get("/lol-perks/v1/inventory")
        if inventory.canAddCustomPage != true {
            let remaining: [PerkPage] = try await client.get("/lol-perks/v1/pages")
            let editable = remaining.filter { $0.isDeletable == true && $0.isEditable == true }
            let victim = editable.first { $0.isTemporary == true } ?? (allowOverwrite ? editable.first { $0.current == true } ?? editable.first : nil)
            guard let victim else {
                throw LCUError.http(0, tr("No free rune page. Enable overwriting in Settings or delete a page."))
            }
            try await client.delete("/lol-perks/v1/pages/\(victim.id)")
        }

        let body: [String: Any] = [
            "name": "\(pagePrefix) \(championName) · \(setup.source)",
            "primaryStyleId": setup.primaryStyleId,
            "subStyleId": setup.subStyleId,
            "selectedPerkIds": setup.perkIds,
            "current": true,
        ]
        try await client.post("/lol-perks/v1/pages", body)
    }

    /// Sets summoner spells in champ select, keeping Flash on the preferred key.
    static func setSpells(_ spells: [Int], flashOnF: Bool, client: LCUClient) async throws {
        guard spells.count == 2 else { return }
        var ordered = spells
        let flash = 4
        if let index = ordered.firstIndex(of: flash) {
            ordered.remove(at: index)
            flashOnF ? ordered.append(flash) : ordered.insert(flash, at: 0)
        }
        try await client.patch("/lol-champ-select/v1/session/my-selection",
                               ["spell1Id": ordered[0], "spell2Id": ordered[1]])
    }

    /// Writes an item set for the champion, replacing the previous toolkit set for it.
    static func importItemSet(_ build: ChampionBuild, championName: String, summonerId: Int, mapId: Int,
                              client: LCUClient) async throws {
        let path = "/lol-item-sets/v1/item-sets/\(summonerId)/sets"
        let data = try await client.request("GET", path)
        var root = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        var sets = (root["itemSets"] as? [[String: Any]]) ?? []
        sets.removeAll { ($0["title"] as? String)?.hasPrefix(pagePrefix) == true
            && ($0["associatedChampions"] as? [Int])?.contains(build.championId) == true }

        func block(_ title: String, _ stats: [ChampionBuild.Stat], limit: Int) -> [String: Any]? {
            var seen = Set<Int>()
            let ids = stats.prefix(limit).flatMap(\.ids).filter { seen.insert($0).inserted }
            guard !ids.isEmpty else { return nil }
            return ["type": title, "items": ids.map { ["id": String($0), "count": 1] }]
        }

        let blocks = [
            block(tr("Starter"), build.starterItems, limit: 2),
            block(tr("Boots"), build.boots, limit: 2),
            block(tr("Core build (%d%% WR)", Int((build.coreItems.first?.winRate ?? 0) * 100)), build.coreItems, limit: 1),
            block(tr("Alternatives"), Array(build.coreItems.dropFirst()), limit: 3),
            block(tr("Late game"), build.lastItems, limit: 8),
            ["type": "Consumables", "items": [["id": "2003", "count": 1], ["id": "2055", "count": 1], ["id": "3340", "count": 1]]],
        ].compactMap { $0 }

        sets.append([
            "uid": UUID().uuidString.lowercased(),
            "title": "\(pagePrefix) \(championName)\(build.lane.map { " \($0.title)" } ?? "")",
            "type": "custom", "map": "any", "mode": "any",
            "associatedChampions": [build.championId], "associatedMaps": [mapId],
            "sortrank": 0, "startedFrom": "blank", "preferredItemSlots": [],
            "blocks": blocks,
        ])
        root["itemSets"] = sets
        root["accountId"] = summonerId
        root["timestamp"] = Int(Date().timeIntervalSince1970 * 1000)
        try await client.put(path, root)
    }

    static func deleteToolkitPages(client: LCUClient) async throws -> Int {
        let pages: [PerkPage] = try await client.get("/lol-perks/v1/pages")
        let ours = pages.filter { $0.name.hasPrefix(pagePrefix) && $0.isDeletable == true }
        for page in ours { try await client.delete("/lol-perks/v1/pages/\(page.id)") }
        return ours.count
    }
}

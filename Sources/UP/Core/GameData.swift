import AppKit
import Foundation
import SwiftUI

/// Static champion, rune, item and spell data read from the client's bundled game data.
@MainActor
@Observable
final class GameData {
    private(set) var champions: [Int: ChampionSummary] = [:]
    private(set) var perks: [Int: PerkInfo] = [:]
    private(set) var styles: [Int: PerkStyleList.Style] = [:]
    private(set) var items: [Int: ItemInfo] = [:]
    private(set) var spells: [Int: SummonerSpellInfo] = [:]
    private(set) var isLoaded = false
    private(set) var details: [Int: ChampionDetail] = [:]

    func detail(_ id: Int, client: LCUClient?) async -> ChampionDetail? {
        if let cached = details[id] { return cached }
        guard let client, id > 0,
              let detail: ChampionDetail = try? await client.get("/lol-game-data/assets/v1/champions/\(id).json") else { return nil }
        details[id] = detail
        return detail
    }

    static func rankEmblemURL(_ tier: String?) -> String? {
        guard let tier, !tier.isEmpty, tier != "NONE" else { return nil }
        return "https://raw.communitydragon.org/latest/plugins/rcp-fe-lol-static-assets/global/default/images/ranked-emblem/emblem-\(tier.lowercased()).png"
    }

    var sortedChampions: [ChampionSummary] {
        champions.values.filter { $0.id > 0 }.sorted { $0.name < $1.name }
    }

    func load(using client: LCUClient) async {
        async let champs: [ChampionSummary]? = try? client.get("/lol-game-data/assets/v1/champion-summary.json")
        async let perkList: [PerkInfo]? = try? client.get("/lol-game-data/assets/v1/perks.json")
        async let styleList: PerkStyleList? = try? client.get("/lol-game-data/assets/v1/perkstyles.json")
        async let itemList: [ItemInfo]? = try? client.get("/lol-game-data/assets/v1/items.json")
        async let spellList: [SummonerSpellInfo]? = try? client.get("/lol-game-data/assets/v1/summoner-spells.json")

        champions = Dictionary((await champs ?? []).filter { $0.id < 10_000 }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        perks = Dictionary((await perkList ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        styles = Dictionary((await styleList?.styles ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        items = Dictionary((await itemList ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        spells = Dictionary((await spellList ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        isLoaded = !champions.isEmpty
    }

    func championName(_ id: Int?) -> String {
        guard let id, id > 0 else { return "—" }
        return champions[id]?.name ?? "#\(id)"
    }

    func champion(named name: String) -> ChampionSummary? {
        let key = name.lowercased().filter(\.isLetter)
        return champions.values.first {
            $0.alias.lowercased() == key || $0.name.lowercased().filter(\.isLetter) == key
        }
    }

    func championIcon(_ id: Int?) -> String? {
        guard let id, id > 0 else { return nil }
        return "/lol-game-data/assets/v1/champion-icons/\(id).png"
    }

    func itemPrice(_ id: Int) -> Int { items[id]?.priceTotal ?? 0 }
}

/// Loads and caches images served by the League client (they require LCU auth).
@MainActor
final class ImageCache {
    static let shared = ImageCache()
    var client: LCUClient?
    private var cache: [String: NSImage] = [:]
    private var inflight: [String: Task<NSImage?, Never>] = [:]

    func image(for path: String) async -> NSImage? {
        if let cached = cache[path] { return cached }
        if let task = inflight[path] { return await task.value }
        let remote = path.hasPrefix("https://")
        guard remote || client != nil else { return nil }
        let client = self.client
        let task = Task<NSImage?, Never> {
            let data: Data?
            if remote, let url = URL(string: path) {
                data = try? await URLSession.shared.data(from: url).0
            } else {
                data = try? await client?.request("GET", path)
            }
            return data.flatMap(NSImage.init(data:))
        }
        inflight[path] = task
        let image = await task.value
        inflight[path] = nil
        if let image { cache[path] = image }
        return image
    }
}

/// Image loaded from a client asset path or https URL, fixed-size when `size` is set.
struct LCUImage: View {
    let path: String?
    var size: CGFloat? = 32
    var corner: CGFloat = 6
    var fill: Color = Color(hex: 0x152039)
    var contentMode: ContentMode = .fit
    var crop: CGRect?
    var alignment: Alignment = .center
    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: alignment) {
            RoundedRectangle(cornerRadius: corner, style: .continuous).fill(fill)
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .task(id: path) {
            image = nil
            guard let path else { return }
            var loaded = await ImageCache.shared.image(for: path)
            if let crop, let cg = loaded?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let rect = CGRect(x: crop.minX * CGFloat(cg.width), y: crop.minY * CGFloat(cg.height),
                                  width: crop.width * CGFloat(cg.width), height: crop.height * CGFloat(cg.height))
                loaded = cg.cropping(to: rect).map { NSImage(cgImage: $0, size: rect.size) }
            }
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}

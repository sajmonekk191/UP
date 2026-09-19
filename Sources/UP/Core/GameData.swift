import AppKit
import Foundation
import SwiftUI

/// Static champion, rune, item and spell data read from the client's bundled game data.
@MainActor
@Observable
final class GameData {
    private(set) var champions: [Int: ChampionSummary] = [:]
    private(set) var sortedChampions: [ChampionSummary] = []
    private(set) var perks: [Int: PerkInfo] = [:]
    private(set) var styles: [Int: PerkStyleList.Style] = [:]
    private(set) var items: [Int: ItemInfo] = [:]
    private(set) var spells: [Int: SummonerSpellInfo] = [:]
    private(set) var isLoaded = false
    private(set) var details: [Int: ChampionDetail] = [:]
    @ObservationIgnored private var byKey: [String: ChampionSummary] = [:]
    @ObservationIgnored private var pendingDetails: [Int: Task<ChampionDetail?, Never>] = [:]

    func detail(_ id: Int, client: LCUClient?) async -> ChampionDetail? {
        if let cached = details[id] { return cached }
        if let pending = pendingDetails[id] { return await pending.value }
        guard let client, id > 0 else { return nil }
        let task = Task<ChampionDetail?, Never> { try? await client.get("/lol-game-data/assets/v1/champions/\(id).json") }
        pendingDetails[id] = task
        let detail = await task.value
        pendingDetails[id] = nil
        if let detail { details[id] = detail }
        return detail
    }

    /// Loads the details of several champions at once.
    func prefetchDetails(_ ids: [Int], client: LCUClient?) async {
        await withTaskGroup(of: Void.self) { group in
            for id in Set(ids) where details[id] == nil {
                group.addTask { _ = await self.detail(id, client: client) }
            }
        }
    }

    static func rankEmblemURL(_ tier: String?) -> String? {
        guard let tier, !tier.isEmpty, tier != "NONE" else { return nil }
        return "https://raw.communitydragon.org/latest/plugins/rcp-fe-lol-static-assets/global/default/images/ranked-emblem/emblem-\(tier.lowercased()).png"
    }

    func load(using client: LCUClient) async {
        async let champs: [ChampionSummary]? = try? client.get("/lol-game-data/assets/v1/champion-summary.json")
        async let perkList: [PerkInfo]? = try? client.get("/lol-game-data/assets/v1/perks.json")
        async let styleList: PerkStyleList? = try? client.get("/lol-game-data/assets/v1/perkstyles.json")
        async let itemList: [ItemInfo]? = try? client.get("/lol-game-data/assets/v1/items.json")
        async let spellList: [SummonerSpellInfo]? = try? client.get("/lol-game-data/assets/v1/summoner-spells.json")

        champions = Dictionary((await champs ?? []).filter { $0.id > 0 && $0.id < 10_000 }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        sortedChampions = champions.values.sorted { $0.name < $1.name }
        byKey = [:]
        for champion in sortedChampions {
            byKey[Self.key(champion.alias)] = champion
            byKey[Self.key(champion.name)] = byKey[Self.key(champion.name)] ?? champion
        }
        perks = Dictionary((await perkList ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        styles = Dictionary((await styleList?.styles ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        items = Dictionary((await itemList ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        spells = Dictionary((await spellList ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        isLoaded = !champions.isEmpty
    }

    private static func key(_ name: String) -> String { name.lowercased().filter(\.isLetter) }

    func championName(_ id: Int?) -> String {
        guard let id, id > 0 else { return "—" }
        return champions[id]?.name ?? "#\(id)"
    }

    /// Champion by its display name or internal alias, as the live game reports it.
    func champion(named name: String) -> ChampionSummary? {
        byKey[Self.key(name)]
    }

    func championIcon(_ id: Int?) -> String? {
        guard let id, id > 0 else { return nil }
        return "/lol-game-data/assets/v1/champion-icons/\(id).png"
    }
}

/// Loads and caches images served by the League client (they require LCU auth).
@MainActor
final class ImageCache {
    static let shared = ImageCache()
    var client: LCUClient?
    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 256 * 1024 * 1024
        return cache
    }()
    private var inflight: [String: Task<CGImage?, Never>] = [:]

    /// Already loaded image, without waiting.
    func cached(_ key: String) -> NSImage? { cache.object(forKey: key as NSString) }

    func image(for path: String, crop: CGRect? = nil) async -> NSImage? {
        let key = Self.key(path, crop)
        if let hit = cached(key) { return hit }
        if let crop {
            guard let source = await image(for: path), let cropped = Self.crop(source, to: crop) else { return nil }
            store(cropped, key)
            return cropped
        }
        let task: Task<CGImage?, Never>
        if let pending = inflight[path] {
            task = pending
        } else {
            let remote = path.hasPrefix("https://")
            guard remote || client != nil else { return nil }
            let client = self.client
            task = Task.detached(priority: .userInitiated) {
                let data: Data?
                if remote, let url = URL(string: path) {
                    data = try? await URLSession.shared.data(from: url).0
                } else {
                    data = try? await client?.request("GET", path)
                }
                return data.flatMap(Self.decode)
            }
            inflight[path] = task
        }
        let decoded = await task.value
        inflight[path] = nil
        if let hit = cached(key) { return hit }
        guard let decoded else { return nil }
        let image = NSImage(cgImage: decoded, size: NSSize(width: decoded.width, height: decoded.height))
        store(image, path)
        return image
    }

    /// Decodes the image data right away, so drawing it later costs the main thread nothing.
    nonisolated private static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    static func key(_ path: String, _ crop: CGRect?) -> String {
        crop.map { "\(path)#\($0.minX),\($0.minY),\($0.width),\($0.height)" } ?? path
    }

    private func store(_ image: NSImage, _ key: String) {
        let pixels = image.representations.map { $0.pixelsWide * $0.pixelsHigh }.max() ?? 0
        cache.setObject(image, forKey: key as NSString, cost: max(pixels * 4, 1))
    }

    private static func crop(_ image: NSImage, to crop: CGRect) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rect = CGRect(x: crop.minX * CGFloat(cg.width), y: crop.minY * CGFloat(cg.height),
                          width: crop.width * CGFloat(cg.width), height: crop.height * CGFloat(cg.height))
        return cg.cropping(to: rect).map { NSImage(cgImage: $0, size: rect.size) }
    }
}

/// Image loaded from a client asset path or https URL, fixed-size when `size` is set.
struct LCUImage: View {
    let path: String?
    var size: CGFloat? = 32
    var corner: CGFloat = 6
    var fill: Color = Theme.raised
    var contentMode: ContentMode = .fit
    var crop: CGRect?
    @State private var image: NSImage?

    init(path: String?, size: CGFloat? = 32, corner: CGFloat = 6, fill: Color = Theme.raised, contentMode: ContentMode = .fit, crop: CGRect? = nil) {
        self.path = path
        self.size = size
        self.corner = corner
        self.fill = fill
        self.contentMode = contentMode
        self.crop = crop
        _image = State(initialValue: path.flatMap { ImageCache.shared.cached(ImageCache.key($0, crop)) })
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous).fill(fill)
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .task(id: path) {
            guard let path else { image = nil; return }
            if let hit = ImageCache.shared.cached(ImageCache.key(path, crop)) { image = hit; return }
            image = nil
            let loaded = await ImageCache.shared.image(for: path, crop: crop)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}

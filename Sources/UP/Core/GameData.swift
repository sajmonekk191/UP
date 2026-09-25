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
    private(set) var augments: [Int: AugmentInfo] = [:]
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

    /// Loads the Arena augments the first time an Arena build needs them.
    func loadAugments(client: LCUClient?) async {
        guard augments.isEmpty, let client, let list: [AugmentInfo] = try? await client.get("/lol-game-data/assets/v1/cherry-augments.json") else { return }
        augments = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
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

/// Loads and caches images served by the League client (they require LCU auth), decoded no larger than they are drawn.
@MainActor
final class ImageCache {
    static let shared = ImageCache()
    var client: LCUClient?
    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()
    private var inflight: [String: Task<(image: CGImage, scaled: Bool)?, Never>] = [:]

    /// Already loaded image that is sharp at `maxPixels`, without waiting; a full-size copy always qualifies.
    func cached(_ path: String, crop: CGRect? = nil, maxPixels: Int? = nil) -> NSImage? {
        let full = cache.object(forKey: Self.key(path, crop, nil) as NSString)
        guard let maxPixels else { return full }
        return cache.object(forKey: Self.key(path, crop, maxPixels) as NSString) ?? full
    }

    /// Image at `path`, cut to `crop` (unit rect from the top left) and scaled down to `maxPixels` on its longer side.
    func image(for path: String, crop: CGRect? = nil, maxPixels: Int? = nil) async -> NSImage? {
        if let hit = cached(path, crop: crop, maxPixels: maxPixels) { return hit }
        let key = Self.key(path, crop, maxPixels)
        let task: Task<(image: CGImage, scaled: Bool)?, Never>
        if let pending = inflight[key] {
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
                return data.flatMap { Self.decode($0, crop: crop, maxPixels: maxPixels) }
            }
            inflight[key] = task
        }
        let decoded = await task.value
        inflight[key] = nil
        if let hit = cached(path, crop: crop, maxPixels: maxPixels) { return hit }
        guard let decoded else { return nil }
        let image = NSImage(cgImage: decoded.image, size: NSSize(width: decoded.image.width, height: decoded.image.height))
        cache.setObject(image, forKey: (decoded.scaled ? key : Self.key(path, crop, nil)) as NSString,
                        cost: decoded.image.width * decoded.image.height * 4)
        return image
    }

    /// Decodes the image right away, so drawing it costs the main thread nothing; `scaled` is set when it came out smaller than the source.
    nonisolated private static func decode(_ data: Data, crop: CGRect?, maxPixels: Int?) -> (image: CGImage, scaled: Bool)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        if let crop {
            return CGImageSourceCreateImageAtIndex(source, 0, nil).flatMap { cropped($0, to: crop, maxPixels: maxPixels) }
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let longest = max(properties?[kCGImagePropertyPixelWidth] as? Int ?? 0, properties?[kCGImagePropertyPixelHeight] as? Int ?? 0)
        if let maxPixels, longest > maxPixels {
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                                            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { ($0, true) }
        }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary).map { ($0, false) }
    }

    /// The `crop` part of `image` redrawn into a bitmap of its own, so the much larger source can be freed.
    nonisolated private static func cropped(_ image: CGImage, to crop: CGRect, maxPixels: Int?) -> (image: CGImage, scaled: Bool)? {
        let rect = CGRect(x: crop.minX * CGFloat(image.width), y: crop.minY * CGFloat(image.height),
                          width: crop.width * CGFloat(image.width), height: crop.height * CGFloat(image.height)).integral
        let scale = min(1, CGFloat(maxPixels ?? .max) / max(rect.width, rect.height, 1))
        let width = max(Int((rect.width * scale).rounded()), 1), height = max(Int((rect.height * scale).rounded()), 1)
        guard let part = image.cropping(to: rect),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(part, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage().map { ($0, scale < 1) }
    }

    private static func key(_ path: String, _ crop: CGRect?, _ maxPixels: Int?) -> String {
        var key = path
        if let crop { key += "#\(crop.minX),\(crop.minY),\(crop.width),\(crop.height)" }
        if let maxPixels { key += "@\(maxPixels)" }
        return key
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
        _image = State(initialValue: path.flatMap { ImageCache.shared.cached($0, crop: crop, maxPixels: Self.pixels(for: size)) })
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
            let pixels = Self.pixels(for: size)
            if let hit = ImageCache.shared.cached(path, crop: crop, maxPixels: pixels) { image = hit; return }
            image = nil
            let loaded = await ImageCache.shared.image(for: path, crop: crop, maxPixels: pixels)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }

    /// Pixels worth decoding for a fixed size: Retina plus room for the scalable HUD, in steps so nearby sizes share one copy.
    private static func pixels(for size: CGFloat?) -> Int? {
        guard let size else { return nil }
        var pixels = 64
        while CGFloat(pixels) < size * 3 { pixels *= 2 }
        return pixels
    }
}

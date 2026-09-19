import Foundation

enum RuneSource: String, CaseIterable, Identifiable {
    case opgg, highElo, riot
    var id: String { rawValue }
    var title: String {
        switch self {
        case .opgg: tr("Most winning (Emerald+)")
        case .highElo: tr("High elo (Master+)")
        case .riot: tr("Riot recommendation")
        }
    }
}

/// User preferences persisted in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    var autoAccept: Bool { didSet { save(autoAccept, "autoAccept") } }
    var acceptDelay: Double { didSet { save(acceptDelay, "acceptDelay") } }
    var autoRunes: Bool { didSet { save(autoRunes, "autoRunes") } }
    var runeSource: RuneSource { didSet { save(runeSource.rawValue, "runeSource") } }
    var importOnHover: Bool { didSet { save(importOnHover, "importOnHover") } }
    var allowOverwritePage: Bool { didSet { save(allowOverwritePage, "allowOverwritePage") } }
    var autoSpells: Bool { didSet { save(autoSpells, "autoSpells") } }
    var flashOnF: Bool { didSet { save(flashOnF, "flashOnF") } }
    var autoItemSets: Bool { didSet { save(autoItemSets, "autoItemSets") } }
    var scoutTeam: Bool { didSet { save(scoutTeam, "scoutTeam") } }
    var soundAlerts: Bool { didSet { save(soundAlerts, "soundAlerts") } }
    var autoPlayAgain: Bool { didSet { save(autoPlayAgain, "autoPlayAgain") } }
    var showOverlay: Bool { didSet { save(showOverlay, "showOverlay") } }
    var autoOpenChampSelect: Bool { didSet { save(autoOpenChampSelect, "autoOpenChampSelect") } }
    var hudToasts: Bool { didSet { save(hudToasts, "hudToasts") } }
    var hudCompact: Bool { didSet { save(hudCompact, "hudCompact") } }
    var hudScale: Double { didSet { save(hudScale, "hudScale") } }

    init() {
        defaults.register(defaults: [
            "autoAccept": true, "acceptDelay": 2.0, "autoRunes": true, "runeSource": RuneSource.opgg.rawValue,
            "importOnHover": false, "allowOverwritePage": true, "autoSpells": true, "flashOnF": true,
            "autoItemSets": true, "scoutTeam": true, "soundAlerts": true, "autoPlayAgain": false,
            "showOverlay": true, "autoOpenChampSelect": true, "hudToasts": true, "hudCompact": false, "hudScale": 1.0,
        ])
        autoAccept = defaults.bool(forKey: "autoAccept")
        acceptDelay = defaults.double(forKey: "acceptDelay")
        autoRunes = defaults.bool(forKey: "autoRunes")
        runeSource = RuneSource(rawValue: defaults.string(forKey: "runeSource") ?? "") ?? .opgg
        importOnHover = defaults.bool(forKey: "importOnHover")
        allowOverwritePage = defaults.bool(forKey: "allowOverwritePage")
        autoSpells = defaults.bool(forKey: "autoSpells")
        flashOnF = defaults.bool(forKey: "flashOnF")
        autoItemSets = defaults.bool(forKey: "autoItemSets")
        scoutTeam = defaults.bool(forKey: "scoutTeam")
        soundAlerts = defaults.bool(forKey: "soundAlerts")
        autoPlayAgain = defaults.bool(forKey: "autoPlayAgain")
        showOverlay = defaults.bool(forKey: "showOverlay")
        autoOpenChampSelect = defaults.bool(forKey: "autoOpenChampSelect")
        hudToasts = defaults.bool(forKey: "hudToasts")
        hudCompact = defaults.bool(forKey: "hudCompact")
        hudScale = defaults.double(forKey: "hudScale")
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }
}

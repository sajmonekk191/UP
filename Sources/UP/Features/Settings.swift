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

/// Where and how the section navigation of the main window is drawn.
enum NavigationStyle: String, CaseIterable, Identifiable {
    case top, league, rail, dock, pill
    var id: String { rawValue }
    var title: String {
        switch self {
        case .top: tr("Top tabs")
        case .league: tr("League-style tabs")
        case .rail: tr("Side rail")
        case .dock: tr("Floating dock")
        case .pill: tr("Compact side pill")
        }
    }
    var next: NavigationStyle { Self.allCases[(Self.allCases.firstIndex(of: self)! + 1) % Self.allCases.count] }
    /// Styles whose section tabs live in the top bar, which moves the search bar to the right.
    var tabsInHeader: Bool { self == .top || self == .league }
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
    var navigationStyle: NavigationStyle { didSet { save(navigationStyle.rawValue, "navigationStyle") } }
    var searchRegion: Region? { didSet { save(searchRegion?.rawValue ?? "", "searchRegion") } }

    init() {
        defaults.register(defaults: [
            "autoAccept": true, "acceptDelay": 2.0, "autoRunes": true, "runeSource": RuneSource.opgg.rawValue,
            "importOnHover": false, "allowOverwritePage": true, "autoSpells": true, "flashOnF": true,
            "autoItemSets": true, "scoutTeam": true, "soundAlerts": true, "autoPlayAgain": false,
            "showOverlay": true, "autoOpenChampSelect": true, "hudToasts": true, "hudCompact": false, "hudScale": 1.0,
            "navigationStyle": NavigationStyle.top.rawValue, "searchRegion": "",
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
        navigationStyle = NavigationStyle(rawValue: defaults.string(forKey: "navigationStyle") ?? "") ?? .top
        searchRegion = Region(rawValue: defaults.string(forKey: "searchRegion") ?? "")
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }
}

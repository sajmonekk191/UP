import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case en, de, fr, es, it, pt, nl, pl, cs, sk

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .en: "English"
        case .de: "Deutsch"
        case .fr: "Français"
        case .es: "Español"
        case .it: "Italiano"
        case .pt: "Português"
        case .nl: "Nederlands"
        case .pl: "Polski"
        case .cs: "Čeština"
        case .sk: "Slovenčina"
        }
    }

    var flag: String {
        switch self {
        case .en: "🇬🇧"
        case .de: "🇩🇪"
        case .fr: "🇫🇷"
        case .es: "🇪🇸"
        case .it: "🇮🇹"
        case .pt: "🇵🇹"
        case .nl: "🇳🇱"
        case .pl: "🇵🇱"
        case .cs: "🇨🇿"
        case .sk: "🇸🇰"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }
}

/// Current UI language; English strings are the lookup keys.
@Observable
final class Localizer: @unchecked Sendable {
    static let shared = Localizer()

    var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "language") }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "language").flatMap(AppLanguage.init)
        let system = Locale.preferredLanguages.first.map { String($0.prefix(2)) }.flatMap(AppLanguage.init)
        language = saved ?? system ?? .en
    }

    func translate(_ key: String) -> String {
        Self.table(for: language)?[key] ?? key
    }

    /// Strings of one language; each table is built on first use, so only the languages shown are loaded.
    private static func table(for language: AppLanguage) -> [String: String]? {
        switch language {
        case .en: nil
        case .de: de
        case .fr: fr
        case .es: es
        case .it: it
        case .pt: pt
        case .nl: nl
        case .pl: pl
        case .cs: cs
        case .sk: sk
        }
    }
}

/// Translates an English UI string, formatting any `%` arguments.
func tr(_ key: String, _ args: CVarArg...) -> String {
    let text = Localizer.shared.translate(key)
    return args.isEmpty ? text : String(format: text, locale: Localizer.shared.language.locale, arguments: args)
}

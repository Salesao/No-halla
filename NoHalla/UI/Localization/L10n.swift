import Foundation

/// In-process localization helper (D10/D12, FR-30).
///
/// All UI text is looked up by its dotted `design/copy.json` key in the
/// bundle of the selected language (`en.lproj` / `ru.lproj`) inside
/// `Bundle.main`. Switching `current` takes effect on the next lookup,
/// so the language can be applied without relaunching the app (D12).
/// English is the fallback when a key or language bundle is missing.
enum L10n {
    /// Current UI language preference. `system` follows the macOS locale.
    /// Set by the General settings tab when the user applies a language change.
    static var current: AppLanguage = .system

    /// Language code ("en" or "ru") resolved from `current`.
    /// `system` maps the first preferred language to EN/RU, defaulting to EN.
    static var resolvedLanguageCode: String {
        switch current {
        case .en:
            return "en"
        case .ru:
            return "ru"
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.hasPrefix("ru") ? "ru" : "en"
        }
    }

    /// Localized string for a dotted copy key, optionally formatted with
    /// printf-style arguments (`%d`, `%@`) via `String(format:)`.
    static func string(_ key: String, _ args: CVarArg...) -> String {
        string(key, arguments: args)
    }

    /// Array-based variant used by the variadic entry point.
    static func string(_ key: String, arguments: [CVarArg]) -> String {
        let template = lookup(key, language: resolvedLanguageCode)
            ?? lookup(key, language: "en")
            ?? key
        guard !arguments.isEmpty else { return template }
        return String(format: template, arguments: arguments)
    }

    /// Reads a key from the given language's `.lproj` bundle.
    /// Returns nil when the bundle or the key is missing.
    private static func lookup(_ key: String, language: String) -> String? {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return nil }
        let value = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
        // localizedString(forKey:) returns the key itself when it is missing.
        return value == key ? nil : value
    }
}

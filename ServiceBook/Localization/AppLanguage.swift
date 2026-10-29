import Foundation

/// The app's display language. `.system` follows the iPhone's language settings.
/// SwiftUI text follows the `locale` environment set at the root; strings built in code go through `L`.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, it, fr, es, pt

    static let key = "appLanguage"
    var id: String { rawValue }

    /// Each language in its own name, so it can be found whatever language is shown.
    var nativeName: String {
        switch self {
        case .system: L("System")
        case .en: "English"
        case .it: "Italiano"
        case .fr: "Français"
        case .es: "Español"
        case .pt: "Português"
        }
    }

    static var selected: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system
    }

    /// Language actually shown: the chosen one, or the first supported language of the iPhone (else English).
    static var code: String {
        if selected != .system { return selected.rawValue }
        let preferred = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages
        return preferred.map { String($0.prefix(2)) }.first { AppLanguage(rawValue: $0) != nil } ?? "en"
    }

    /// The shown language with the user's region, so dates, numbers and currencies keep the local format.
    static var locale: Locale {
        guard let region = Locale.current.region?.identifier else { return Locale(identifier: code) }
        return Locale(identifier: "\(code)_\(region)")
    }

    /// English name of the shown language, used in the AI prompts.
    static var englishName: String {
        Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "English"
    }

    static var bundle: Bundle {
        Bundle.main.path(forResource: code, ofType: "lproj").flatMap { Bundle(path: $0) } ?? .main
    }

    /// Saves the choice. Setting `AppleLanguages` makes system screens (photo picker, scanner…)
    /// follow too from the next launch, and matches iOS Settings → ServiceBook → Language.
    static func select(_ language: AppLanguage) {
        if language == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
        UserDefaults.standard.set(language.rawValue, forKey: key)
    }

    /// Picks up a language chosen in iOS Settings → ServiceBook → Language.
    static func syncWithSystemSettings() {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        let chosen = (domain?["AppleLanguages"] as? [String])?.first.map { String($0.prefix(2)) }
        UserDefaults.standard.set((chosen.flatMap(AppLanguage.init(rawValue:)) ?? .system).rawValue, forKey: key)
    }
}

/// Text from the catalog schedules in the app language: the translations carried by the downloaded files, else
/// Schedules.xcstrings (older built-in schedules). Saved items keep the English text as their key, so they follow
/// the language too; text the user wrote has no entry and is returned as is.
func LS(_ text: String) -> String {
    if let t = ScheduleTranslations.shared.lookup(text, AppLanguage.code) { return t }
    return AppLanguage.bundle.localizedString(forKey: text, value: text, table: "Schedules")
}

/// Localized text in the app language. The key is the English text; arguments use printf formats (%@, %lld).
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = AppLanguage.bundle.localizedString(forKey: key, value: key, table: nil)
    return args.isEmpty ? format : String(format: format, locale: AppLanguage.locale, arguments: args)
}

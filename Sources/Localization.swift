import Foundation

enum AppLanguage: String, CaseIterable {
    case auto   = "auto"
    case en     = "en"
    case zhHans = "zh-Hans"

    var displayName: String {
        switch self {
        case .auto:   return L10n.tr("System Default (Auto)", "跟随系统 (自动)")
        case .en:     return "English"
        case .zhHans: return "简体中文"
        }
    }
}

enum L10n {
    static var language: AppLanguage {
        get {
            let raw = UserDefaults.standard.string(forKey: "KuroCat.Language") ?? "auto"
            return AppLanguage(rawValue: raw) ?? .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "KuroCat.Language")
        }
    }

    static var isChinese: Bool {
        switch language {
        case .en:     return false
        case .zhHans: return true
        case .auto:
            let pref = Locale.preferredLanguages.first ?? "en"
            return pref.lowercased().hasPrefix("zh")
        }
    }

    static func tr(_ en: String, _ zh: String) -> String {
        isChinese ? zh : en
    }
}

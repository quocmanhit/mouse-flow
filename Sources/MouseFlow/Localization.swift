import Foundation

enum Language: String, CaseIterable {
    case english = "en"
    case vietnamese = "vi"

    var title: String {
        switch self {
        case .english: "English"
        case .vietnamese: "Tiếng Việt"
        }
    }

    private static let key = "language"

    // nil until the user picks a language, which the first launch asks for.
    static var saved: Language? {
        get { UserDefaults.standard.string(forKey: key).flatMap(Language.init) }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: key) }
    }

    static var current: Language {
        saved ?? (Locale.preferredLanguages.first?.hasPrefix("vi") == true ? .vietnamese : .english)
    }
}

func tr(_ english: String, _ vietnamese: String) -> String {
    Language.current == .vietnamese ? vietnamese : english
}

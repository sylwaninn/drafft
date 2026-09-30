import Foundation
import Observation

/// App languages offered at sign-up and in You. Defaults to the phone's language when we have
/// it, English otherwise.
enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case en, fr, es, de, it, pt, nl
    var id: String { rawValue }

    /// Name in the language itself, as people look for it.
    var name: String {
        switch self {
        case .en: "English"
        case .fr: "Français"
        case .es: "Español"
        case .de: "Deutsch"
        case .it: "Italiano"
        case .pt: "Português"
        case .nl: "Nederlands"
        }
    }

    /// The language's folder on getdrafft.com, English at the root. No default case: a new
    /// language needs its pages on the site before the app links to them.
    var sitePath: String {
        switch self {
        case .en: ""
        case .fr: "/fr"
        case .es: "/es"
        case .de: "/de"
        case .it: "/it"
        case .pt: "/pt"
        case .nl: "/nl"
        }
    }

    /// Portuguese is European Portuguese (see NotificationText).
    var locale: Locale { Locale(identifier: self == .pt ? "pt_PT" : rawValue) }

    static var deviceDefault: AppLanguage {
        for id in Locale.preferredLanguages {
            let code = Locale(identifier: id).language.languageCode?.identifier ?? ""
            if let l = AppLanguage(rawValue: code) { return l }
        }
        return .en
    }
}

/// The interface language, picked in the app rather than the phone's. SwiftUI text reads it
/// through `\.locale` (set on the root view); strings built in code go through `L(_:)`.
/// Observable, so views that called `L(_:)` redraw when the language changes.
@Observable
final class Localization: @unchecked Sendable { // written on the main actor only
    static let shared = Localization()
    /// The last one picked, kept on the phone so the first screen is already in it (the profile
    /// has it too: NotificationService.applyServer).
    var language: AppLanguage = UserDefaults.standard.string(forKey: "appLanguage").flatMap(AppLanguage.init(rawValue:))
        ?? .deviceDefault {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "appLanguage") }
    }
}

extension Locale {
    /// The app's language, for dates and numbers formatted in code.
    static var app: Locale { Localization.shared.language.locale }
}

/// A string from Localizable.xcstrings in the app's language, for text built in code
/// (component titles, model labels). SwiftUI literals (`Text("…")`) don't need it.
func L(_ resource: LocalizedStringResource) -> String {
    var resource = resource
    resource.locale = .app
    return String(localized: resource)
}

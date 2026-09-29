import SwiftUI

/// The legal documents. Their only text is the one published on getdrafft.com, in the app's
/// language, opened in the in-app browser (`openURL(_:prefersInApp:)`): the app never keeps a copy
/// that could say something else.
enum LegalDoc: String, CaseIterable, Identifiable {
    case terms, privacy, community
    var id: Self { self }

    var title: String {
        switch self {
        case .terms: L("Terms of Use")
        case .privacy: L("Privacy Policy")
        case .community: L("Community Guidelines")
        }
    }

    /// The community guidelines are a section of the terms.
    var url: URL {
        switch self {
        case .terms: Self.page("terms")
        case .privacy: Self.page("privacy")
        case .community: Self.page("terms", section: "community")
        }
    }

    /// The privacy policy's section on sensitive data, linked from the consent to it.
    static var sensitiveData: URL { page("privacy", section: "sensitive-data") }

    /// getdrafft.com/<language>/<page>#<section>, English without a language prefix. Section
    /// anchors are the same in every language.
    static func page(_ page: String, section: String? = nil) -> URL {
        let language = Localization.shared.language
        let prefix = language == .en ? "" : "/\(language.rawValue)"
        let anchor = section.map { "#\($0)" } ?? ""
        return URL(string: "https://getdrafft.com\(prefix)/\(page)\(anchor)")! // swiftlint:disable:this force_unwrapping
    }
}

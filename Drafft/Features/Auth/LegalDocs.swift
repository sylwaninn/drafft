import Foundation

/// The legal documents. Their only text is the one published on getdrafft.com, opened in the
/// in-app browser (`openURL(_:prefersInApp:)`): the app never keeps a copy that could say something
/// else.
enum LegalDoc: CaseIterable, Hashable {
    case terms, privacy, community

    var title: String {
        switch self {
        case .terms: L("Terms of Use")
        case .privacy: L("Privacy Policy")
        case .community: L("Community Guidelines")
        }
    }

    /// The page in `language`, the app's by default. The community guidelines are a section of the
    /// terms.
    func url(in language: AppLanguage = Localization.shared.language) -> URL {
        switch self {
        case .terms: Self.page("terms", in: language)
        case .privacy: Self.page("privacy", in: language)
        case .community: Self.page("terms", section: "community", in: language)
        }
    }

    /// getdrafft.com/<language>/<page>?lang=<code>#<section>, English at the root. The pages switch
    /// to the browser's language unless `lang` names one, and the in-app browser reports the
    /// phone's languages, not the app's: `lang` keeps the page in the app's language. Section
    /// anchors are the same in every language.
    private static func page(_ page: String, section: String? = nil, in language: AppLanguage) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "getdrafft.com"
        components.path = "\(language.sitePath)/\(page)"
        components.queryItems = [URLQueryItem(name: "lang", value: language.rawValue)]
        components.fragment = section
        // An absolute path on a fixed host always makes a URL.
        return components.url! // swiftlint:disable:this force_unwrapping
    }
}

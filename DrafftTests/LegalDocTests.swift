import XCTest

/// The addresses of the legal pages on getdrafft.com: English at the root, the other languages in
/// their folder, `?lang=` always (the pages otherwise switch to the browser's language), and the
/// community guidelines as the terms' `#community` section.
final class LegalDocTests: XCTestCase {
    private let expected: [AppLanguage: [LegalDoc: String]] = [
        .en: [
            .terms: "https://getdrafft.com/terms?lang=en",
            .privacy: "https://getdrafft.com/privacy?lang=en",
            .community: "https://getdrafft.com/terms?lang=en#community",
        ],
        .fr: [
            .terms: "https://getdrafft.com/fr/terms?lang=fr",
            .privacy: "https://getdrafft.com/fr/privacy?lang=fr",
            .community: "https://getdrafft.com/fr/terms?lang=fr#community",
        ],
        .es: [
            .terms: "https://getdrafft.com/es/terms?lang=es",
            .privacy: "https://getdrafft.com/es/privacy?lang=es",
            .community: "https://getdrafft.com/es/terms?lang=es#community",
        ],
        .de: [
            .terms: "https://getdrafft.com/de/terms?lang=de",
            .privacy: "https://getdrafft.com/de/privacy?lang=de",
            .community: "https://getdrafft.com/de/terms?lang=de#community",
        ],
        .it: [
            .terms: "https://getdrafft.com/it/terms?lang=it",
            .privacy: "https://getdrafft.com/it/privacy?lang=it",
            .community: "https://getdrafft.com/it/terms?lang=it#community",
        ],
        .pt: [
            .terms: "https://getdrafft.com/pt/terms?lang=pt",
            .privacy: "https://getdrafft.com/pt/privacy?lang=pt",
            .community: "https://getdrafft.com/pt/terms?lang=pt#community",
        ],
        .nl: [
            .terms: "https://getdrafft.com/nl/terms?lang=nl",
            .privacy: "https://getdrafft.com/nl/privacy?lang=nl",
            .community: "https://getdrafft.com/nl/terms?lang=nl#community",
        ],
    ]

    private var savedLanguage: AppLanguage?
    private var savedStored: Any?

    override func setUp() {
        super.setUp()
        savedLanguage = Localization.shared.language
        savedStored = UserDefaults.standard.object(forKey: "appLanguage")
    }

    override func tearDown() {
        if let savedLanguage { Localization.shared.language = savedLanguage }
        // Setting the language stores it: put back what was there, or nothing.
        UserDefaults.standard.set(savedStored, forKey: "appLanguage")
        super.tearDown()
    }

    func testEveryDocumentInEveryLanguage() {
        XCTAssertEqual(Set(expected.keys), Set(AppLanguage.allCases))
        for language in AppLanguage.allCases {
            for doc in LegalDoc.allCases {
                XCTAssertEqual(doc.url(in: language).absoluteString, expected[language]?[doc], "\(doc) in \(language)")
            }
        }
    }

    func testEnglishHasNoFolder() {
        XCTAssertEqual(LegalDoc.terms.url(in: .en).path, "/terms")
        XCTAssertEqual(AppLanguage.en.sitePath, "")
    }

    func testPortugueseUsesTheSiteFolderNotTheLocale() {
        // The app formats Portuguese as pt_PT, the site's folder is /pt.
        XCTAssertEqual(LegalDoc.privacy.url(in: .pt).path, "/pt/privacy")
        XCTAssertEqual(LegalDoc.privacy.url(in: .pt).query, "lang=pt")
    }

    func testOnlyTheCommunityGuidelinesHaveASection() {
        for language in AppLanguage.allCases {
            XCTAssertEqual(LegalDoc.community.url(in: language).fragment, "community")
            XCTAssertEqual(LegalDoc.community.url(in: language).path, LegalDoc.terms.url(in: language).path)
            XCTAssertNil(LegalDoc.terms.url(in: language).fragment)
            XCTAssertNil(LegalDoc.privacy.url(in: language).fragment)
        }
    }

    func testEveryAddressIsHTTPSOnTheSite() {
        for language in AppLanguage.allCases {
            for doc in LegalDoc.allCases {
                let url = doc.url(in: language)
                XCTAssertEqual(url.scheme, "https")
                XCTAssertEqual(url.host(), "getdrafft.com")
            }
        }
    }

    func testSensitiveDataSectionOfThePrivacyPolicy() {
        XCTAssertEqual(LegalDoc.sensitiveData(in: .en).absoluteString, "https://getdrafft.com/privacy?lang=en#sensitive-data")
        XCTAssertEqual(LegalDoc.sensitiveData(in: .nl).absoluteString, "https://getdrafft.com/nl/privacy?lang=nl#sensitive-data")
        for language in AppLanguage.allCases {
            XCTAssertEqual(LegalDoc.sensitiveData(in: language).path, LegalDoc.privacy.url(in: language).path)
        }
    }

    func testFollowsTheAppLanguageByDefault() {
        Localization.shared.language = .de
        XCTAssertEqual(LegalDoc.terms.url().absoluteString, "https://getdrafft.com/de/terms?lang=de")
        Localization.shared.language = .en
        XCTAssertEqual(LegalDoc.community.url().absoluteString, "https://getdrafft.com/terms?lang=en#community")
    }
}

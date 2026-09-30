import Foundation

/// Sign-up progress saved as it goes, so an unfinished sign-up resumes where it stopped. Kept on
/// this device, under the account it belongs to: another account signing in here never sees it.
struct OnboardingProgress: Codable, Equatable {
    var name = ""
    var language: String?
    var birthday: Date?
    /// The terms version recorded on the server with the consent (`TermsConsent`), nil until then.
    /// It alone says the consent was given: progress saved before it (with an `acceptedTerms` flag,
    /// now ignored) still decodes, and the rules step asks again.
    var termsVersion: String?
    var verifiedPhone: String?
    var identity: String?
    var interestedIn: [String] = []
    var area: String?
    var sports: [SavedSport] = []
    var photos: [String] = []
    var voicePath: String?
    var voiceDuration: TimeInterval = 0
    var prompts: [SavedPrompt] = []
    var bio = ""
    /// Rhythm, food, drinking, smoking ("" when not answered).
    var lifestyle: [String] = []
    /// Furthest step reached.
    var furthest = 0

    struct SavedSport: Codable, Equatable { var sport: String; var perWeek: Int }
    struct SavedPrompt: Codable, Equatable { var question: String; var answer: String }
}

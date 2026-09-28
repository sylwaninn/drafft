import Foundation

/// Sign-up progress saved as it goes, so an unfinished sign-up resumes where it stopped. Kept on
/// this device, under the account it belongs to: another account signing in here never sees it.
struct OnboardingProgress: Codable, Equatable {
    var name = ""
    var language: String?
    var birthday: Date?
    var acceptedTerms = false
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

enum OnboardingStore {
    /// One entry per account id; nothing without a signed-in account.
    private static var key: String? {
        // The old device-wide entry could belong to anyone: dropped, never handed to an account.
        UserDefaults.standard.removeObject(forKey: "onboarding.progress.v2")
        return Backend.shared.client.auth.currentUser.map { "onboarding.progress.v3.\($0.id.uuidString.lowercased())" }
    }

    static func load() -> OnboardingProgress? {
        guard let key, let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(OnboardingProgress.self, from: data)
    }

    static func save(_ p: OnboardingProgress) {
        guard let key, let data = try? JSONEncoder().encode(p) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Clears the signed-in account's progress.
    static func clear() {
        if let key { UserDefaults.standard.removeObject(forKey: key) }
    }

    static var hasUnfinished: Bool { load() != nil }

    /// Photos picked during sign-up live in temp; keep them somewhere that survives relaunches.
    static func persist(photo path: String) -> String {
        let fm = FileManager.default
        guard path.hasPrefix(fm.temporaryDirectory.path),
              let dir = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("SignUpPhotos", isDirectory: true) else { return path }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent((path as NSString).lastPathComponent)
        if !fm.fileExists(atPath: dest.path) { try? fm.copyItem(atPath: path, toPath: dest.path) }
        return dest.path
    }
}

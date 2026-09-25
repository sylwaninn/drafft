import CoreLocation
import Foundation

/// The signed-in person's own profile on the server: sign-up sends everything it collected and
/// opens the profile (`complete_onboarding`), Edit profile saves changes, and launch reads it back.
/// Photos go through `PhotoModeration` (upload, register, moderation) as soon as they're picked;
/// this only waits for them and puts them in order.
enum ProfileSync {
    enum SyncError: Error, LocalizedError {
        /// A photo couldn't be sent (its tile says why).
        case photoUpload
        /// The server refused: its hint code (`underage`, `photo_required`…).
        case refused(String)

        var errorDescription: String? {
            switch self {
            case .photoUpload: L("A photo couldn't be sent. Tap it to see why, then try again.")
            case .refused(let code): Self.message(for: code)
            }
        }

        static func message(for code: String) -> String {
            switch code {
            case "name_required": L("Add your first name.")
            case "underage": L("You need to be 18 or older to use drafft.")
            case "gender_required": L("Pick the one that fits you best.")
            case "sport_required": L("Add at least one sport.")
            case "photo_required": L("Add at least one photo.")
            case "media_limit": L("You can have up to 9 photos and videos.")
            default: L("Something went wrong. Try again in a moment.")
            }
        }
    }

    // MARK: Sign-up

    struct SignUp {
        var name: String
        var birthday: Date
        var gender: String?
        var interestedIn: Set<String>
        var neighborhood: String
        var location: CLLocationCoordinate2D?
        var intent: Intent?
        var bio: String
        var lifestyle: Vitals
        var icebreaker: Icebreaker?
        var sports: [SportEntry]
        var prompts: [ProfilePrompt]
        var photos: [String]
        var voice: (url: URL, duration: TimeInterval, levels: [Float])?
        var language: AppLanguage
    }

    /// Everything sign-up collected, then `complete_onboarding`, which checks the essentials.
    static func finish(_ s: SignUp) async throws {
        var fields: [String: Any] = [
            "name": s.name,
            "birthdate": Self.day.string(from: s.birthday),
            "interested_in": s.interestedIn.contains("Everyone") ? [] : s.interestedIn.compactMap(Self.genderValue),
            "neighborhood": s.neighborhood,
            "bio": s.bio,
            "language": s.language.rawValue
        ]
        if let g = s.gender.flatMap(Self.genderValue) { fields["gender"] = g }
        fields.merge(vitalsFields(s.lifestyle, intent: s.intent)) { $1 }
        if let ice = s.icebreaker { fields["icebreaker"] = ice.json }
        if let voice = s.voice { fields.merge(try await uploadVoice(voice)) { $1 } }
        do { try await Backend.shared.updateMyProfile(fields) } catch { throw refused(error) }
        try await setSports(s.sports)
        try await setPrompts(s.prompts)
        try await syncPhotos(s.photos)
        if let c = s.location {
            _ = try? await Backend.shared.rpc("set_location", ["p_lat": c.latitude, "p_lng": c.longitude])
        }
        do { _ = try await Backend.shared.rpc("complete_onboarding", [:]) } catch { throw refused(error) }
    }

    // MARK: Edit profile

    /// Saves Edit profile's changes (the birthday stays as set at sign-up).
    static func save(_ p: Profile, previous: Profile, voice: (url: URL, duration: TimeInterval, levels: [Float])?) async throws {
        var fields: [String: Any] = [
            "name": p.name,
            "bio": p.bio,
            "goal": p.goal,
            "favorite_spot": p.favoriteSpot,
            "icebreaker": p.icebreaker.isComplete ? p.icebreaker.json : NSNull()
        ]
        fields.merge(vitalsFields(p.vitals ?? .blank, intent: p.vitals?.intent)) { $1 }
        if let voice { fields.merge(try await uploadVoice(voice)) { $1 } }
        do { try await Backend.shared.updateMyProfile(fields) } catch { throw refused(error) }
        if p.sports != previous.sports { try await setSports(p.sports) }
        if p.prompts != previous.prompts { try await setPrompts(p.prompts) }
        if p.allPhotos != previous.allPhotos { try await syncPhotos(p.allPhotos) }
    }

    // MARK: Read back

    /// The person's profile as saved, for a new device or a reinstall. Photos are the approved and
    /// pending ones (their own), as public URLs.
    static func load() async throws -> Profile? {
        guard let id = await Backend.shared.userID else { return nil }
        struct Row: Decodable {
            let name: String
            let birthdate: String?
            let pronouns: String?
            let neighborhood: String
            let bio: String
            let goal: String
            let favorite_spot: String
            let intent: String?
            let drinks: String
            let smokes: String
            let diet: String
            let chronotype: String
            let icebreaker: JSONValue?
            let voice_intro_key: String?
            let voice_duration: Double?
        }
        struct SportRow: Decodable { let sport_id: String; let per_week: Int }
        struct PromptRow: Decodable { let question: String; let answer: String }
        struct MediaRow: Decodable { let id: String; let key: String; let kind: String; let status: String }

        let decoder = JSONDecoder()
        guard let row = try decoder.decode([Row].self, from: await Backend.shared.select(
            "profiles?id=eq.\(id)&select=name,birthdate,pronouns,neighborhood,bio,goal,favorite_spot,intent,drinks,smokes,diet,chronotype,icebreaker,voice_intro_key,voice_duration"
        )).first else { return nil }
        let sports = try decoder.decode([SportRow].self, from: await Backend.shared.select(
            "profile_sports?user_id=eq.\(id)&select=sport_id,per_week&order=position"))
        let prompts = try decoder.decode([PromptRow].self, from: await Backend.shared.select(
            "profile_prompts?user_id=eq.\(id)&select=question,answer&order=position"))
        let media = try decoder.decode([MediaRow].self, from: await Backend.shared.select(
            "profile_media?user_id=eq.\(id)&select=id,key,kind,status&order=position"))

        let base = await MediaURL.base()
        let photos = media.filter { $0.kind == "photo" && $0.status != "rejected" }
            .compactMap { m -> String? in base.map { $0.appendingPathComponent(m.key).absoluteString } }
        let age = row.birthdate.flatMap(Self.day.date(from:)).map {
            Calendar.current.dateComponents([.year], from: $0, to: .now).year ?? 18
        } ?? 18
        var vitals = Vitals(intent: row.intent.flatMap(Intent.init(rawValue:)), drinks: row.drinks, smokes: row.smokes,
                            diet: row.diet, chronotype: row.chronotype)
        if vitals.intent == nil && !vitals.hasLifestyle { vitals = .blank }
        return Profile(
            id: "me",
            name: row.name,
            age: age,
            pronouns: row.pronouns,
            neighborhood: row.neighborhood,
            distanceKm: 0,
            portrait: photos.first ?? "",
            photos: Array(photos.dropFirst()),
            sports: sports.compactMap { s in Sport(rawValue: s.sport_id).map { SportEntry(sport: $0, perWeek: s.per_week) } },
            voiceIntro: row.voice_intro_key.flatMap { key in base.map { $0.appendingPathComponent(key).absoluteString } },
            voiceDuration: row.voice_duration ?? 0,
            icebreaker: row.icebreaker.flatMap(Icebreaker.init(json:)) ?? Icebreaker.Kind.twoTruths.blank,
            favoriteSpot: row.favorite_spot,
            bio: row.bio,
            goal: row.goal,
            vitalsOverride: vitals,
            promptsOverride: prompts.map { ProfilePrompt(question: $0.question, answer: $0.answer) }
        )
    }

    // MARK: Pieces

    private static func setSports(_ sports: [SportEntry]) async throws {
        let list = sports.map { ["sport": $0.sport.rawValue, "perWeek": $0.perWeek] as [String: Any] }
        do { _ = try await Backend.shared.rpc("set_sports", ["p_sports": list]) } catch { throw refused(error) }
    }

    private static func setPrompts(_ prompts: [ProfilePrompt]) async throws {
        let list = prompts.filter { !$0.answer.trimmingCharacters(in: .whitespaces).isEmpty }
            .prefix(3).map { ["question": $0.question, "answer": $0.answer] }
        do { _ = try await Backend.shared.rpc("set_prompts", ["p_prompts": Array(list)]) } catch { throw refused(error) }
    }

    /// Waits for the picked photos to reach the server, drops the ones taken off the profile, and
    /// puts the rest in the profile's order. Photos already on the server (URLs) keep their id.
    private static func syncPhotos(_ photos: [String]) async throws {
        for path in photos where path.hasPrefix("/") {
            guard await PhotoModeration.shared.waitForID(path) != nil else { throw SyncError.photoUpload }
        }
        guard let me = await Backend.shared.userID else { return }
        struct Media: Decodable { let id: String; let key: String }
        let onServer = try JSONDecoder().decode([Media].self, from: await Backend.shared.select(
            "profile_media?user_id=eq.\(me)&select=id,key&order=position"))
        // Photos loaded from the server are URLs: matched by their key.
        let order = await photos.asyncCompactMap { path -> String? in
            if path.hasPrefix("http") { return onServer.first { path.hasSuffix("/" + $0.key) }?.id }
            return await PhotoModeration.shared.id(for: path)
        }
        for m in onServer where !order.contains(m.id) {
            _ = try? await Backend.shared.rpc("delete_media", ["p_id": m.id])
        }
        if order.count > 1 {
            do { _ = try await Backend.shared.rpc("reorder_media", ["p_ids": order]) } catch { throw refused(error) }
        }
    }

    /// Uploads a voice intro (.m4a) and returns the profile columns that point to it.
    private static func uploadVoice(_ voice: (url: URL, duration: TimeInterval, levels: [Float])) async throws -> [String: Any] {
        let key = try await MediaUploads.voice(voice.url, tickets: tickets)
        var fields: [String: Any] = ["voice_intro_key": key, "voice_duration": min(60, voice.duration)]
        if !voice.levels.isEmpty { fields["voice_levels"] = Array(voice.levels.prefix(200)).map(Double.init) }
        return fields
    }

    private static var tickets: EdgeFunctionTicketProvider {
        EdgeFunctionTicketProvider(functionsURL: BackendConfig.functionsURL) { try await Backend.shared.accessToken() }
    }

    private static func vitalsFields(_ v: Vitals, intent: Intent?) -> [String: Any] {
        ["intent": intent?.rawValue ?? NSNull(), "drinks": v.drinks, "smokes": v.smokes, "diet": v.diet,
         "chronotype": v.chronotype]
    }

    /// Sign-up's gender answers (kept in English) as the server's values.
    private static func genderValue(_ answer: String) -> String? {
        switch answer {
        case "Woman", "Women": "woman"
        case "Man", "Men": "man"
        case "Non-binary", "Non-binary people": "nonbinary"
        default: nil
        }
    }

    /// Server errors carry a stable code in `hint`: turned into the message people see.
    private static func refused(_ error: Error) -> Error {
        if case Backend.BackendError.http(_, let hint) = error, !hint.contains(" ") { return SyncError.refused(hint) }
        return error
    }

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

extension Sequence {
    fileprivate func asyncCompactMap<T>(_ transform: (Element) async -> T?) async -> [T] {
        var out: [T] = []
        for e in self { if let t = await transform(e) { out.append(t) } }
        return out
    }
}

// MARK: - Icebreaker on the server

extension Icebreaker {
    /// The `profiles.icebreaker` shape: `{ "kind": "joke", "setup": …, "punchline": … }`.
    var json: [String: Any] {
        switch self {
        case let .twoTruths(statements, lieIndex): ["kind": "twoTruths", "statements": statements, "lieIndex": lieIndex]
        case let .joke(setup, punchline): ["kind": "joke", "setup": setup, "punchline": punchline]
        case let .hotTake(text): ["kind": "hotTake", "text": text]
        case let .thisOrThat(question, options, pick): ["kind": "thisOrThat", "question": question, "options": options, "pick": pick]
        case let .guess(question, options, answer): ["kind": "guess", "question": question, "options": options, "answer": answer]
        }
    }

    init?(json value: JSONValue) {
        guard case .object(let o) = value, case .string(let kind)? = o["kind"] else { return nil }
        func str(_ k: String) -> String { if case .string(let s)? = o[k] { return s }; return "" }
        func int(_ k: String) -> Int { if case .number(let n)? = o[k] { return Int(n) }; return -1 }
        func strings(_ k: String) -> [String] {
            if case .array(let a)? = o[k] { return a.compactMap { if case .string(let s) = $0 { return s }; return nil } }
            return []
        }
        switch kind {
        case "twoTruths": self = .twoTruths(statements: strings("statements"), lieIndex: int("lieIndex"))
        case "joke": self = .joke(setup: str("setup"), punchline: str("punchline"))
        case "hotTake": self = .hotTake(str("text"))
        case "thisOrThat": self = .thisOrThat(question: str("question"), options: strings("options"), pick: int("pick"))
        case "guess": self = .guess(question: str("question"), options: strings("options"), answer: int("answer"))
        default: return nil
        }
    }
}

/// Any JSON value (for columns whose shape varies, like the icebreaker).
enum JSONValue: Decodable, Hashable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
}

// MARK: - Media URLs

/// Where uploaded media is served from (R2 public URL, later the CDN domain). Asked once from the
/// backend (`app-config`), then kept on the phone.
enum MediaURL {
    private static let key = "mediaBaseURL"

    static func base() async -> URL? {
        if let saved = UserDefaults.standard.string(forKey: key), let url = URL(string: saved) { return url }
        struct Config: Decodable { let mediaUrl: String }
        guard let (data, _) = try? await URLSession.shared.data(from: BackendConfig.functionsURL.appendingPathComponent("app-config")),
              let config = try? JSONDecoder().decode(Config.self, from: data),
              let url = URL(string: config.mediaUrl) else { return nil }
        UserDefaults.standard.set(config.mediaUrl, forKey: key)
        return url
    }
}

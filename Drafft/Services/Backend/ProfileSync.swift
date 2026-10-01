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
        /// The profile on the server wasn't read in this session: saving could overwrite it.
        case notLoaded
        /// A photo of the draft is no longer on the server (removed from another screen or device).
        case photoGone

        var errorDescription: String? {
            switch self {
            case .photoUpload: L("A photo couldn't be sent. Tap it to see why, then try again.")
            case .notLoaded: L("Your profile hasn't loaded, so nothing was saved. Close and try again.")
            case .photoGone: L("A photo is no longer there, so nothing was saved. Close and try again.")
            case .refused(let code): Self.message(for: code)
            }
        }

        static func message(for code: String) -> String {
            ServerMessage.text(forCode: code) ?? ServerMessage.generic
        }
    }

    /// The account whose server profile was read (or sent by sign-up) in this session. Edit profile
    /// only saves over that one: never over a profile it didn't see.
    @MainActor static var loadedAccount: UUID?

    // MARK: Sign-up

    struct SignUp {
        var name: String
        var birthday: Date
        var gender: String?
        var interestedIn: Set<String>
        var neighborhood: String
        var location: CLLocationCoordinate2D?
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
        fields.merge(vitalsFields(s.lifestyle)) { $1 }
        if let ice = s.icebreaker { fields["icebreaker"] = ice.json }
        if let voice = s.voice { fields.merge(try await uploadVoice(voice)) { $1 } }
        // Independent writes go out together (one round trip of waiting, not five), then
        // `complete_onboarding` checks the result.
        let location = s.location
        async let profile: Void = updateProfile(fields)
        async let sports: Void = setSports(s.sports)
        async let prompts: Void = setPrompts(s.prompts)
        async let photos: Void = syncPhotos(s.photos, previous: [])
        async let area: Void = setLocation(location)
        _ = try await (profile, sports, prompts, photos, area)
        do { _ = try await Backend.shared.rpc("complete_onboarding", [:]) } catch { throw refused(error) }
        let id = await Backend.shared.userID
        await MainActor.run { loadedAccount = id }
    }

    // MARK: Edit profile

    /// Saves Edit profile's changes (the birthday stays as set at sign-up).
    static func save(_ p: Profile, previous: Profile, voice: (url: URL, duration: TimeInterval, levels: [Float])?) async throws {
        try await requireLoaded()
        var fields: [String: Any] = [
            "name": p.name,
            "bio": p.bio,
            "goal": p.goal,
            "favorite_spot": p.favoriteSpot,
            "icebreaker": p.icebreaker.isComplete ? p.icebreaker.json : NSNull()
        ]
        fields.merge(vitalsFields(p.vitals ?? .blank)) { $1 }
        if let voice { fields.merge(try await uploadVoice(voice)) { $1 } }
        // Only what changed, all at once.
        let sportsChanged = p.sports != previous.sports, promptsChanged = p.prompts != previous.prompts
        let photosChanged = p.allPhotos != previous.allPhotos
        async let profile: Void = updateProfile(fields)
        async let sports: Void = sportsChanged ? setSports(p.sports) : ()
        async let prompts: Void = promptsChanged ? setPrompts(p.prompts) : ()
        async let photos: Void = photosChanged ? syncPhotos(p.allPhotos, previous: previous.allPhotos, loadedFirst: true) : ()
        _ = try await (profile, sports, prompts, photos)
    }

    /// Throws unless this session read the signed-in account's profile from the server.
    private static func requireLoaded() async throws {
        let id = await Backend.shared.userID
        guard let id, await loadedAccount == id else { throw SyncError.notLoaded }
    }

    // MARK: Read back

    /// Everything the app shows of the account's own profile row, read in one request: the
    /// profile (with its sports, prompts and photos), the pause, a moderation hold, whether sign-up
    /// is finished, and the notification settings. One read, shared by every screen that needs it
    /// (instead of one read per piece); it's also what the local cache keeps.
    /// One of the account's photos as the server has it: its link (as the grids show it), its id and
    /// moderation's word (`approved`, `pending`, `rejected`).
    struct OwnPhoto: Sendable {
        let link: String
        let id: String
        let status: String
        /// The server found no face on it (the portrait needs one). False when it did, or never checked.
        var faceless = false
    }

    struct Account: Sendable {
        /// Every photo the person has, refused ones included: they stay on the person's own grid (to
        /// ask for a second look), and only approved ones show as the profile (`PhotoModeration`).
        let profile: Profile
        let photos: [OwnPhoto]
        let paused: Bool
        let hold: AccountHold?
        let onboarded: Bool
        let notifications: NotificationSettings?
        /// Whether the consent is on record for the current terms (`TermsConsent.Gate`): only a
        /// fresh read may say `.required`.
        let consent: TermsConsent.Gate
    }

    /// The row as the server sends it; the local cache stores these bytes as they are.
    private struct AccountRow: Decodable {
        let name: String
        let birthdate: String?
        let pronouns: String?
        let gender: String?
        let neighborhood: String
        let bio: String
        let goal: String
        let favoriteSpot: String
        let drinks: String
        let smokes: String
        let diet: String
        let chronotype: String
        let icebreaker: JSONValue?
        let voiceIntroKey: String?
        let voiceDuration: Double?
        let paused: Bool
        let moderation: AccountHold?
        let onboardedAt: String?
        let sports: [SportRow]?
        let prompts: [PromptRow]?
        let media: [MediaRow]?

        enum CodingKeys: String, CodingKey {
            case name, birthdate, pronouns, gender, neighborhood, bio, goal, drinks, smokes, diet, chronotype
            case icebreaker, paused, moderation
            case favoriteSpot = "favorite_spot"
            case voiceIntroKey = "voice_intro_key"
            case voiceDuration = "voice_duration"
            case onboardedAt = "onboarded_at"
            case sports = "profile_sports"
            case prompts = "profile_prompts"
            case media = "profile_media"
        }

        struct SportRow: Decodable {
            let sportID: String
            let perWeek: Int
            enum CodingKeys: String, CodingKey { case sportID = "sport_id", perWeek = "per_week" }
        }
        struct PromptRow: Decodable { let question: String; let answer: String }
        struct MediaRow: Decodable {
            let id: String; let key: String; let kind: String; let status: String; let thumbhash: String?
            // Three states in the column: a face, none, never checked (null).
            // swiftlint:disable:next discouraged_optional_boolean
            let face: Bool?
        }
    }

    /// Filled by `accept_terms` (read by `TermsConsent.Columns`); drafft-backend #48 adds them.
    private static let consentColumns = ["terms_version", "terms_accepted_at", "sensitive_consent_at"]

    private static func accountColumns(withConsent: Bool) -> String {
        ([
            "name", "birthdate", "pronouns", "gender", "neighborhood", "bio", "goal", "favorite_spot",
            "drinks", "smokes", "diet", "chronotype", "icebreaker", "voice_intro_key", "voice_duration",
            "paused", "moderation", "onboarded_at", NotificationSettings.columns,
            "profile_sports(sport_id,per_week)", "profile_prompts(question,answer)", "profile_media(id,key,kind,status,thumbhash,face)"
        ] + (withConsent ? consentColumns : [])).joined(separator: ",")
    }

    /// The account as saved on the server (a new device, a reinstall, another device's changes), in
    /// one request with its sports, prompts and media embedded. Photos are the approved and pending
    /// ones (their own), as signed links (the bucket is private). Also returns the raw bytes, for the
    /// local cache: they hold keys only, never a link, so a cached copy never carries an expired one.
    static func loadAccount() async throws -> (account: Account, data: Data)? {
        guard let id = await Backend.shared.userID else { return nil }
        func read(withConsent: Bool) async throws -> Data {
            try await Backend.shared.select(
                "profiles?id=eq.\(id)&select=\(accountColumns(withConsent: withConsent))"
                    + "&profile_sports.order=position&profile_prompts.order=position&profile_media.order=position"
                    // Drafts (picked, never saved) are never the profile, even the person's own.
                    + "&profile_media.published_at=not.is.null")
        }
        let data: Data
        do {
            data = try await read(withConsent: true)
        } catch Backend.BackendError.http(400, let message) where consentColumns.contains(where: { message.contains($0) }) {
            // A backend from before the consent columns (42703, the column doesn't exist): the
            // account is read without them, and the consent stays unknown until it has them.
            TermsConsent.log.error("The profile has no consent columns (drafft-backend #48 not deployed): \(message, privacy: .public)")
            data = try await read(withConsent: false)
        }
        let keys = mediaKeys(in: data)
        let signed = await MediaURL.signed(keys)
        // A backend from before signed links: the public base URL + key.
        let base = signed.count == keys.count ? MediaURL.saved : await MediaURL.base()
        guard let account = decodeAccount(data, mediaBase: base, signed: signed) else { return nil }
        await MainActor.run { loadedAccount = id }
        return (account, data)
    }

    /// The media keys a row shows (every photo, the voice intro), to sign in one request.
    private static func mediaKeys(in data: Data) -> [String] {
        guard let row = (try? JSONDecoder().decode([AccountRow].self, from: data))?.first else { return [] }
        return (row.media ?? []).filter { $0.kind == "photo" }.map(\.key)
            + [row.voiceIntroKey].compactMap { $0 }
    }

    /// The account from the server's bytes (a fresh read, or the copy in the local cache). Media links:
    /// the signed one for a key when there is one, else the base URL + key (the cached copy at launch:
    /// photos then come from the image cache, keyed by object, until the fresh read signs them).
    static func decodeAccount(_ data: Data, mediaBase base: URL?, signed: [String: String] = [:]) -> Account? {
        guard let row = (try? JSONDecoder().decode([AccountRow].self, from: data))?.first else { return nil }
        func link(_ key: String) -> String? { signed[key] ?? base.map { $0.appendingPathComponent(key).absoluteString } }
        // Each photo's blurred preview, shown while it loads.
        for m in row.media ?? [] { MediaPreviews.register(m.thumbhash, key: m.key) }
        let own = (row.media ?? []).filter { $0.kind == "photo" }.compactMap { m in
            link(m.key).map { OwnPhoto(link: $0, id: m.id, status: m.status, faceless: m.face == false) }
        }
        let photos = own.map(\.link)
        let age = row.birthdate.flatMap(Self.day.date(from:)).map {
            Calendar.current.dateComponents([.year], from: $0, to: .now).year ?? 18
        } ?? 18
        var vitals = Vitals(drinks: row.drinks, smokes: row.smokes, diet: row.diet, chronotype: row.chronotype)
        if !vitals.hasLifestyle { vitals = .blank }
        let profile = Profile(
            id: "me",
            name: row.name,
            age: age,
            pronouns: row.pronouns,
            birthday: row.birthdate.flatMap(Self.day.date(from:)),
            gender: row.gender.flatMap(DiscoverFilters.Audience.init(answer:)),
            neighborhood: row.neighborhood,
            distanceKm: 0,
            portrait: photos.first ?? "",
            photos: Array(photos.dropFirst()),
            sports: (row.sports ?? []).compactMap { s in
                Sport(rawValue: s.sportID).map { SportEntry(sport: $0, perWeek: s.perWeek) }
            },
            voiceIntro: row.voiceIntroKey.flatMap(link),
            voiceDuration: row.voiceDuration ?? 0,
            icebreaker: row.icebreaker.flatMap(Icebreaker.init(json:)) ?? Icebreaker.Kind.twoTruths.blank,
            favoriteSpot: row.favoriteSpot,
            bio: row.bio,
            goal: row.goal,
            vitalsOverride: vitals,
            promptsOverride: (row.prompts ?? []).map { ProfilePrompt(question: $0.question, answer: $0.answer) }
        )
        return Account(
            profile: profile, photos: own, paused: row.paused, hold: row.moderation, onboarded: row.onboardedAt != nil,
            notifications: try? JSONDecoder().decode([NotificationSettings].self, from: data).first,
            consent: TermsConsent.gate(fromProfileRow: data)
        )
    }

    // MARK: Pieces

    private static func updateProfile(_ fields: sending [String: Any]) async throws {
        do { try await Backend.shared.updateMyProfile(fields) } catch { throw refused(error) }
    }

    /// Best effort: the area can be set again later from the app.
    private static func setLocation(_ c: CLLocationCoordinate2D?) async {
        guard let c else { return }
        _ = try? await Backend.shared.rpc("set_location", ["p_lat": c.latitude, "p_lng": c.longitude])
    }

    private static func setSports(_ sports: [SportEntry]) async throws {
        let list = sports.map { ["sport": $0.sport.rawValue, "perWeek": $0.perWeek] as [String: Any] }
        do { _ = try await Backend.shared.rpc("set_sports", ["p_sports": list]) } catch { throw refused(error) }
    }

    private static func setPrompts(_ prompts: [ProfilePrompt]) async throws {
        let list = prompts.filter { !$0.answer.trimmingCharacters(in: .whitespaces).isEmpty }
            .prefix(3).map { ["question": $0.question, "answer": $0.answer] }
        do { _ = try await Backend.shared.rpc("set_prompts", ["p_prompts": Array(list)]) } catch { throw refused(error) }
    }

    /// Waits for the picked photos to reach the server, then saves the profile's photos in one go
    /// (`save_profile_media`): the list is published in its order, the photos of `previous` no longer in it
    /// are deleted. Picked photos stay drafts, off the profile, until this runs. Photos already on the
    /// server (links) keep their id. From Edit profile (`loadedFirst`), only once the server's profile was
    /// read in this session: otherwise `previous` could be another profile's.
    private static func syncPhotos(_ photos: [String], previous: [String], loadedFirst: Bool = false) async throws {
        if loadedFirst { try await requireLoaded() }
        let photos = try await uploaded(photos)
        guard let me = await Backend.shared.userID else { throw Backend.BackendError.signedOut }
        let ids = try await mediaIDs(of: me)
        var order: [String] = []
        for path in photos {
            // Gone meanwhile: nothing is saved rather than a profile without it.
            guard let id = await ids(path) else { throw SyncError.photoGone }
            order.append(id)
        }
        var removed: [String] = []
        for path in previous where !path.isEmpty && !photos.contains(path) {
            if let id = await ids(path), !order.contains(id) { removed.append(id) }
        }
        do {
            _ = try await Backend.shared.rpc("save_profile_media", ["p_ids": order, "p_removed": removed])
        } catch {
            if ServerMessage.code(of: error) == "not_found" { throw SyncError.photoGone }
            throw refused(error)
        }
    }

    /// The photos once every picked one is on the server (registered, moderation may still run).
    private static func uploaded(_ photos: [String]) async throws -> [String] {
        // Only picked files and server URLs: anything else isn't a photo of this account.
        let photos = photos.filter { !$0.isEmpty }
        guard photos.allSatisfy({ $0.hasPrefix("/") || $0.hasPrefix("http") }) else { throw SyncError.notLoaded }
        for path in photos where path.hasPrefix("/") {
            guard await PhotoModeration.shared.waitForID(path) != nil else { throw SyncError.photoUpload }
        }
        return photos
    }

    /// How to find a photo's server id: a link loaded from the server (signed: the key is its path) by
    /// its key, a picked file by what its upload registered.
    private static func mediaIDs(of me: UUID) async throws -> @Sendable (String) async -> String? {
        struct Media: Decodable { let id: String; let key: String }
        let onServer = try JSONDecoder().decode([Media].self, from: await Backend.shared.select(
            "profile_media?user_id=eq.\(me)&select=id,key&order=position"))
        return { path in
            if path.hasPrefix("http") {
                let key = URL(string: path).flatMap(MediaURL.key(of:))
                return onServer.first { $0.key == key }?.id
            }
            return await PhotoModeration.shared.id(for: path)
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

    private static func vitalsFields(_ v: Vitals) -> [String: Any] {
        ["drinks": v.drinks, "smokes": v.smokes, "diet": v.diet, "chronotype": v.chronotype]
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
        if let code = ServerMessage.code(of: error) { return SyncError.refused(code) }
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

/// Media links. The bucket is private: the backend signs a link for each object the person may see
/// (cards, `media_urls`), valid for about an hour. Caches are keyed by the object (`canonical`), never
/// by the signature. `base()` is where media is served from (`app-config`), for builds and backends from
/// before signed links.
enum MediaURL {
    private static let key = "mediaBaseURL"

    /// The base already known on this phone, without asking (nil before the first `base()`).
    static var saved: URL? { UserDefaults.standard.string(forKey: key).flatMap(URL.init(string:)) }

    static func base() async -> URL? {
        if let saved = UserDefaults.standard.string(forKey: key), let url = URL(string: saved) { return url }
        struct Config: Decodable { let mediaUrl: String }
        guard let (data, _) = try? await URLSession.shared.data(from: BackendConfig.functionsURL.appendingPathComponent("app-config")),
              let config = try? JSONDecoder().decode(Config.self, from: data),
              let url = URL(string: config.mediaUrl) else { return nil }
        UserDefaults.standard.set(config.mediaUrl, forKey: key)
        return url
    }

    /// Signed links for keys the app holds: its own media, and chat media of a current match. Keys the
    /// person may not open are left out; empty when offline.
    static func signed(_ keys: [String]) async -> [String: String] {
        guard !keys.isEmpty,
              let data = try? await Backend.shared.rpc("media_urls", ["p_keys": keys]),
              let urls = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return urls
    }

    /// The object key of a media link (`u/<user>/…`, its path after the base), or nil.
    nonisolated static func key(of url: URL) -> String? {
        guard let start = url.path.range(of: "/u/") else { return nil }
        return String(url.path[url.path.index(after: start.lowerBound)...])
    }

    /// The same object (and width, `w`) whatever its signature: what caches are keyed by.
    nonisolated static func canonical(_ url: URL) -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let width = parts.queryItems?.filter { $0.name == "w" } ?? []
        parts.queryItems = width.isEmpty ? nil : width
        return parts.url ?? url
    }

    /// When a signed link stops working; nil for an unsigned one.
    nonisolated static func expiry(of url: URL) -> Date? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "exp" }?.value.flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
    }

    /// The link while it has more than a minute left; otherwise a new one from the backend (own and
    /// chat media: cards come with fresh links each time they're read again), or the same link.
    /// The width asked of the media Worker (`w`) is kept.
    static func fresh(_ url: URL) async -> URL {
        guard let expiry = expiry(of: url), expiry.timeIntervalSinceNow < 60, let key = key(of: url),
              let renewed = await signed([key])[key].flatMap(URL.init(string:)) else { return url }
        guard let width = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "w" }),
              var parts = URLComponents(url: renewed, resolvingAgainstBaseURL: false) else { return renewed }
        parts.queryItems = (parts.queryItems ?? []).filter { $0.name != "w" } + [width]
        return parts.url ?? renewed
    }
}

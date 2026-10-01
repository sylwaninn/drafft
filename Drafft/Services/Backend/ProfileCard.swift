import Foundation

/// Someone else's profile as the server sends it: a `profile_cards` row (`private.rebuild_card`)
/// plus what each function adds (`discover`, `liked_me`, `my_matches`, `get_cards`). Foundation only,
/// so the decoding is tested on its own (DrafftTests).
///
/// Media links are signed by the server for the viewer and expire after about an hour: a card is
/// never kept longer than that (`DeckCache.maxAge`), and images are cached by object, not by link.
struct ProfileCard: Decodable, Sendable, Equatable {
    let id: String
    let name: String
    let gender: String?
    let pronouns: String?
    let neighborhood: String
    let bio: String
    let goal: String
    let favoriteSpot: String
    let vitals: Lifestyle?
    let icebreaker: IcebreakerRow?
    let voiceIntro: Voice?
    let media: [Media]
    let sports: [SportRow]
    let prompts: [Prompt]
    /// Null from `get_cards` for someone who liked the viewer before finishing sign-up.
    let age: Int?
    /// `discover` only: at least 1.
    let distanceKm: Int?
    let superLikedMe: Bool
    let superLikeNote: String?
    /// Bumped by the server each time the card changes.
    let cardVersion: Int64

    struct Lifestyle: Decodable, Sendable, Equatable {
        let drinks: String?
        let smokes: String?
        let diet: String?
        let chronotype: String?
    }

    /// `profiles.icebreaker`: `{ "kind": "joke", "setup": …, "punchline": … }`, fields by kind.
    struct IcebreakerRow: Decodable, Sendable, Equatable {
        let kind: String
        let statements: [String]?
        let lieIndex: Int?
        let setup: String?
        let punchline: String?
        let text: String?
        let question: String?
        let options: [String]?
        let pick: Int?
        let answer: Int?
    }

    struct Voice: Decodable, Sendable, Equatable {
        let key: String
        let url: String?
        let duration: Double?
        let levels: [Float]?
    }

    struct Media: Decodable, Sendable, Equatable {
        let id: String
        let kind: String
        let key: String
        /// Signed for this viewer; nil when the server may not sign it (then nothing can open it).
        let url: String?
        /// Blurred preview shown while the photo loads (`MediaPreviews`).
        var thumbhash: String?
        /// Size in pixels (nil for older rows): picks the copy to download (`Renditions`).
        var width: Int?
        var height: Int?
    }

    struct SportRow: Decodable, Sendable, Equatable {
        let sport: String
        let perWeek: Int
    }

    struct Prompt: Decodable, Sendable, Equatable {
        let question: String
        let answer: String
    }

    enum CodingKeys: String, CodingKey {
        case id, name, gender, pronouns, neighborhood, bio, goal, favoriteSpot, vitals, icebreaker, voiceIntro
        case media, sports, prompts, age, distanceKm, superLikedMe, superLikeNote, cardVersion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Ids are compared as the app prints them.
        id = try c.decode(String.self, forKey: .id).lowercased()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        gender = try c.decodeIfPresent(String.self, forKey: .gender)
        pronouns = try c.decodeIfPresent(String.self, forKey: .pronouns)
        neighborhood = try c.decodeIfPresent(String.self, forKey: .neighborhood) ?? ""
        bio = try c.decodeIfPresent(String.self, forKey: .bio) ?? ""
        goal = try c.decodeIfPresent(String.self, forKey: .goal) ?? ""
        favoriteSpot = try c.decodeIfPresent(String.self, forKey: .favoriteSpot) ?? ""
        vitals = try? c.decodeIfPresent(Lifestyle.self, forKey: .vitals)
        // A malformed icebreaker hides the icebreaker, never the whole card.
        icebreaker = try? c.decodeIfPresent(IcebreakerRow.self, forKey: .icebreaker)
        voiceIntro = try? c.decodeIfPresent(Voice.self, forKey: .voiceIntro)
        media = try c.decodeIfPresent([Media].self, forKey: .media) ?? []
        sports = try c.decodeIfPresent([SportRow].self, forKey: .sports) ?? []
        prompts = try c.decodeIfPresent([Prompt].self, forKey: .prompts) ?? []
        age = try c.decodeIfPresent(Int.self, forKey: .age)
        distanceKm = try c.decodeIfPresent(Int.self, forKey: .distanceKm)
        superLikedMe = try c.decodeIfPresent(Bool.self, forKey: .superLikedMe) ?? false
        superLikeNote = try c.decodeIfPresent(String.self, forKey: .superLikeNote)
        cardVersion = try c.decodeIfPresent(Int64.self, forKey: .cardVersion) ?? 0
    }

    /// Photo links in the profile's order (videos aside). The signed link when there is one, else
    /// `base` + key (a backend from before signed links).
    func photoLinks(base: URL?) -> [String] {
        media.filter { $0.kind == "photo" }.compactMap { m in
            m.url ?? base.map { $0.appendingPathComponent(m.key).absoluteString }
        }
    }

    /// Whether it can be shown: a name, an age and at least one photo.
    var isShowable: Bool { !name.isEmpty && age != nil && media.contains { $0.kind == "photo" } }

    /// Decodes a list, skipping any element that doesn't decode (one odd card never empties a deck).
    static func list(from data: Data) throws -> [ProfileCard] {
        try JSONDecoder().decode([Lenient<ProfileCard>].self, from: data).compactMap(\.value)
    }
}

/// `liked_me`: a card plus the like itself.
struct LikeCard: Decodable, Sendable, Equatable {
    let card: ProfileCard
    let likedAt: String?

    init(from decoder: Decoder) throws {
        card = try ProfileCard(from: decoder)
        enum Keys: String, CodingKey { case likedAt }
        likedAt = try decoder.container(keyedBy: Keys.self).decodeIfPresent(String.self, forKey: .likedAt)
    }

    static func list(from data: Data) throws -> [LikeCard] {
        try JSONDecoder().decode([Lenient<LikeCard>].self, from: data).compactMap(\.value)
    }
}

/// `my_matches`: `{ matchId, matchedAt, profile }`.
struct MatchRow: Decodable, Sendable, Equatable {
    let matchId: String
    let matchedAt: String
    let profile: ProfileCard

    enum CodingKeys: String, CodingKey { case matchId, matchedAt, profile }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        matchId = try c.decode(String.self, forKey: .matchId).lowercased()
        matchedAt = try c.decode(String.self, forKey: .matchedAt)
        profile = try c.decode(ProfileCard.self, forKey: .profile)
    }

    static func list(from data: Data) throws -> [MatchRow] {
        try JSONDecoder().decode([Lenient<MatchRow>].self, from: data).compactMap(\.value)
    }
}

/// An element that may fail to decode: nil then, instead of failing the whole array.
private struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// Merging a fresh batch into the deck on screen.
enum DeckMerge {
    /// The server's fresh order, with the first `keep` cards on screen left in place when they're still
    /// in it (the stack doesn't reshuffle under the person's thumb), and without anything swiped
    /// meanwhile (`exclude`: swipes still on their way to the server). A card on screen that the fresh
    /// batch no longer has is dropped: paused, blocked, swiped on another device, or no longer
    /// eligible. No duplicates.
    static func merge<ID: Hashable>(current: [ID], fresh: [ID], keep: Int, exclude: Set<ID>) -> [ID] {
        let available = Set(fresh)
        var seen = exclude
        var out: [ID] = []
        for id in current.prefix(keep) where available.contains(id) && seen.insert(id).inserted { out.append(id) }
        for id in fresh where seen.insert(id).inserted { out.append(id) }
        return out
    }
}

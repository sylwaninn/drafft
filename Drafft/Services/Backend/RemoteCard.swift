import Foundation

/// Another person's profile card, as the backend sends it (`my_matches`, `get_cards`: `profile_cards.card`
/// with `age`, and a signed `url` on each media item the person may see).
struct RemoteCard: Decodable {
    let id: String
    let name: String
    let age: Int?
    let pronouns: String?
    let gender: String?
    let neighborhood: String?
    let bio: String?
    let goal: String?
    let favoriteSpot: String?
    let vitals: VitalsRow?
    let icebreaker: JSONValue?
    let voiceIntro: Voice?
    let media: [Media]?
    let sports: [SportRow]?
    let prompts: [PromptRow]?

    struct VitalsRow: Decodable { let drinks, smokes, diet, chronotype: String? }
    struct Voice: Decodable { let key: String?; let url: String?; let duration: Double? }
    struct Media: Decodable { let kind: String?; let key: String?; let url: String? }
    struct SportRow: Decodable { let sport: String; let perWeek: Int? }
    struct PromptRow: Decodable { let question: String; let answer: String }

    /// Photos only, as signed links, in order (no link: not visible to this person right now).
    var photoLinks: [String] { (media ?? []).filter { $0.kind == nil || $0.kind == "photo" }.compactMap(\.url) }

    var profile: Profile {
        let photos = photoLinks
        var v = Vitals(drinks: vitals?.drinks ?? "", smokes: vitals?.smokes ?? "", diet: vitals?.diet ?? "",
                       chronotype: vitals?.chronotype ?? "")
        if !v.hasLifestyle { v = .blank }
        return Profile(
            id: id.lowercased(),
            name: name,
            age: age ?? 18,
            pronouns: pronouns,
            gender: gender.flatMap(DiscoverFilters.Audience.init(answer:)),
            neighborhood: neighborhood ?? "",
            distanceKm: 0,
            portrait: photos.first ?? "",
            photos: Array(photos.dropFirst()),
            sports: (sports ?? []).compactMap { s in Sport(rawValue: s.sport).map { SportEntry(sport: $0, perWeek: s.perWeek ?? 1) } },
            voiceIntro: voiceIntro?.url,
            voiceDuration: voiceIntro?.duration ?? 0,
            icebreaker: icebreaker.flatMap(Icebreaker.init(json:)) ?? Icebreaker.Kind.twoTruths.blank,
            favoriteSpot: favoriteSpot ?? "",
            bio: bio ?? "",
            goal: goal ?? "",
            vitalsOverride: v,
            promptsOverride: (prompts ?? []).map { ProfilePrompt(question: $0.question, answer: $0.answer) }
        )
    }

    /// The signed link of one of this card's objects (a liked photo), if it's on the card.
    func link(forKey key: String) -> String? {
        (media ?? []).first { $0.key == key }?.url
    }
}

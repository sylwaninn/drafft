import Foundation

/// Cards from the server as the app's `Profile`, and what the discovery calls send.
extension ProfileCard {
    /// The profile the screens show. `base`: the media base for a backend from before signed links.
    func profile(mediaBase base: URL?) -> Profile {
        // Each photo's blurred preview, shown while it loads.
        for m in media { MediaPreviews.register(m.thumbhash, key: m.key) }
        let photos = photoLinks(base: base)
        var lifestyle = Vitals(drinks: vitals?.drinks ?? "", smokes: vitals?.smokes ?? "",
                               diet: vitals?.diet ?? "", chronotype: vitals?.chronotype ?? "")
        if !lifestyle.hasLifestyle { lifestyle = .blank }
        return Profile(
            id: id,
            name: name,
            age: age ?? 18,
            pronouns: pronouns,
            gender: gender.flatMap(DiscoverFilters.Audience.init(answer:)),
            neighborhood: neighborhood,
            distanceKm: Double(distanceKm ?? 0),
            portrait: photos.first ?? "",
            photos: Array(photos.dropFirst()),
            sports: sports.compactMap { s in Sport(rawValue: s.sport).map { SportEntry(sport: $0, perWeek: s.perWeek) } },
            voiceIntro: voiceIntro.flatMap { v in v.url ?? base.map { $0.appendingPathComponent(v.key).absoluteString } },
            voiceDuration: voiceIntro?.duration ?? 0,
            icebreaker: icebreaker?.icebreaker ?? Icebreaker.Kind.twoTruths.blank,
            favoriteSpot: favoriteSpot,
            bio: bio,
            goal: goal,
            superLikedMe: superLikedMe,
            superLikeNote: superLikeNote.flatMap { $0.isEmpty ? nil : $0 },
            vitalsOverride: lifestyle,
            promptsOverride: prompts.map { ProfilePrompt(question: $0.question, answer: $0.answer) }
        )
    }
}

extension ProfileCard.IcebreakerRow {
    /// The app's icebreaker; nil for a kind this version doesn't know.
    var icebreaker: Icebreaker? {
        switch kind {
        case "twoTruths": .twoTruths(statements: statements ?? [], lieIndex: lieIndex ?? -1)
        case "joke": .joke(setup: setup ?? "", punchline: punchline ?? "")
        case "hotTake": .hotTake(text ?? "")
        case "thisOrThat": .thisOrThat(question: question ?? "", options: options ?? [], pick: pick ?? -1)
        case "guess": .guess(question: question ?? "", options: options ?? [], answer: answer ?? -1)
        default: nil
        }
    }
}

extension DiscoverFilters {
    /// `discover`'s `p_filters` (docs/matching.md, Filters): the last stops of the sliders ("50+ km",
    /// "60+") and Everyone send nothing, so the server applies no limit or the person's own preferences.
    var serverFilters: [String: Any] {
        var f: [String: Any] = ["minAge": ages.lowerBound]
        if !anyDistance { f["maxDistanceKm"] = Int(maxDistanceKm) }
        if ages.upperBound < Self.ageBounds.upperBound { f["maxAge"] = ages.upperBound }
        let genders: [String] = switch audience {
        case .women: ["woman"]
        case .men: ["man"]
        case .nonBinary: ["nonbinary"]
        case .everyone: []
        }
        if !genders.isEmpty { f["audience"] = genders }
        if !sports.isEmpty { f["sports"] = sports.map(\.rawValue).sorted() }
        if sharedSportsOnly { f["sharedSportsOnly"] = true }
        return f
    }
}

extension MessageContent {
    /// The first message a like carries (`swipes.opener`), posted in the chat if it becomes a match. A
    /// session becomes a real session proposal. Nil for content a like can't carry.
    var opener: [String: Any]? {
        switch self {
        case .text(let text):
            return ["kind": "text", "text": text]
        case let .icebreakerReply(quote, reply):
            return ["kind": "icebreakerReply", "quote": quote, "reply": reply]
        case let .photoReply(asset, reply):
            // The photo's object key, never its signed link (it expires).
            var o: [String: Any] = ["kind": "photoReply", "reply": reply]
            if let key = URL(string: asset).flatMap(MediaURL.key(of:)) { o["key"] = key }
            return o
        case .session(let s):
            let iso = ISO8601DateFormatter()
            var o: [String: Any] = [
                "kind": "session", "sport": s.sport.rawValue, "options": s.options.map { iso.string(from: $0) },
                "title": s.title, "note": s.note, "tags": s.tags
            ]
            switch s.discovery {
            case .iTeach: o["discovery"] = "iTeach"
            case .theyTeach: o["discovery"] = "theyTeach"
            case nil: break
            }
            return o
        case .photo, .video, .voice, .file:
            return nil
        }
    }
}

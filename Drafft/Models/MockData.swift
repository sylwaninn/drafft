import Foundation

/// Synthetic demo content. Every person, photo, voice and conversation here is a placeholder.
enum MockData {
    static func audio(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "m4a")
    }

    static let profiles: [Profile] = [
        Profile(
            id: "maya", name: "Maya", age: 29, pronouns: "she/her", neighborhood: "Belleville", distanceKm: 2.4, portrait: "portrait_maya", photos: ["sport_trail", "sport_boulder", "sport_hike"],
            sports: [.init(sport: .trail, perWeek: 2), .init(sport: .climbing, perWeek: 2), .init(sport: .yoga, perWeek: 1)],
            voiceIntro: "intro_maya",
            voiceDuration: 12.7,
            icebreaker: .twoTruths(statements: [
                "I once finished a trail race with one shoe.",
                "I've never fallen off a bouldering wall.",
                "I can name every bakery on the Buttes-Chaumont loop."
            ], lieIndex: 1),
            favoriteSpot: "Buttes-Chaumont hills",
            bio: "Physio who spends her own weekends getting injured on purpose. Slow long runs, fast brunches.",
            goal: "First 50k ultra in October"
        ),
        Profile(
            id: "leo", name: "Alexandre-Maxime", age: 32, pronouns: "he/him", neighborhood: "Bastille", distanceKm: 1.1, portrait: "portrait_leo", photos: ["sport_peloton", "sport_bike", "sport_clay"],
            sports: [.init(sport: .cycling, perWeek: 2), .init(sport: .padel, perWeek: 2)],
            voiceIntro: "intro_leo",
            voiceDuration: 12.4,
            icebreaker: .thisOrThat(question: "Saturday morning:", options: ["Sunrise ride", "Padel then brunch"], pick: 0),
            favoriteSpot: "Longchamp loop at 7am",
            bio: "Saturday club rides, weeknight padel, and far too many opinions on bike wheels.",
            goal: "Ride the Ventoux, all three sides"
        ),
        Profile(
            id: "sam", name: "Sam", age: 34, pronouns: "they/them", neighborhood: "République", distanceKm: 0.8, portrait: "portrait_sam", photos: ["sport_barbell", "sport_ropes", "sport_pullup"],
            sports: [.init(sport: .strength, perWeek: 2), .init(sport: .crossfit, perWeek: 1), .init(sport: .running, perWeek: 1)],
            voiceIntro: "intro_sam",
            voiceDuration: 10.1,
            icebreaker: .joke(setup: "I told my client to stop doing squats.", punchline: "They took it lying down. Bench day, apparently."),
            favoriteSpot: "The rack by the window",
            bio: "Coach. Good form, bad puns. Will spot you and remember your PRs.",
            goal: "200 kg deadlift by spring"
        ),
        Profile(
            id: "chloe", name: "Chloé", age: 31, pronouns: "she/her", neighborhood: "Canal Saint-Martin", distanceKm: 1.6, portrait: "portrait_chloe", photos: ["sport_groupnight", "sport_sunsetrun", "sport_stairs"],
            sports: [.init(sport: .running, perWeek: 3), .init(sport: .triathlon, perWeek: 1)],
            voiceIntro: "intro_chloe",
            voiceDuration: 9.5,
            icebreaker: .twoTruths(statements: [
                "I've run a marathon dressed as a baguette.",
                "I have never once skipped a warm-up.",
                "My resting heart rate is 44."
            ], lieIndex: 1),
            favoriteSpot: "Canal Saint-Martin at dawn",
            bio: "Intervals on Tuesdays, long runs on Sundays, croissants always.",
            goal: "Sub-3:30 marathon in Berlin"
        ),
        Profile(
            id: "noah", name: "Noah", age: 30, pronouns: "he/him", neighborhood: "Montreuil", distanceKm: 5.2, portrait: "portrait_noah", photos: ["sport_cliff", "sport_hike", "sport_boulder"],
            sports: [.init(sport: .climbing, perWeek: 3), .init(sport: .hiking, perWeek: 1)],
            voiceIntro: "intro_noah",
            voiceDuration: 10.7,
            icebreaker: .hotTake("Top-roping is more romantic than bouldering. Someone literally holds your life."),
            favoriteSpot: "Arkose Montreuil",
            bio: "Draws for a living, climbs to stay sane. Mountains most weekends.",
            goal: "Send my first 7a outdoors"
        )
    ]

    static func profile(_ id: String) -> Profile { profiles.first { $0.id == id }! }

    /// Whether a person (or their chat, same id) is one of these samples. Samples stay in the app, but
    /// nothing real happens for them: no upload or server check, no notification, no session reminder.
    static func isSample(_ id: String) -> Bool { sampleIDs.contains(id) }
    private static let sampleIDs = Set(profiles.map(\.id))

    static func conversations() -> [Conversation] {
        let now = Date.now
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

        var maya = Conversation(id: "maya", profile: profile("maya"), messages: [], matchedAt: ago(60 * 26))
        maya.messages = [
            Message(.icebreakerReply(quote: "I've never fallen off a bouldering wall.", reply: "Calling it: #2 is the lie. Nobody has never fallen off a wall 😄"), fromMe: true, date: ago(60 * 25)),
            Message(.text("Caught. I fall off walls weekly. It's part of the charm."), fromMe: false, date: ago(60 * 24.8)),
            Message(.text("Where do you usually run on Sundays?"), fromMe: true, date: ago(60 * 24.5)),
            Message(.photo(asset: "sport_trail", imageData: nil), fromMe: false, date: ago(60 * 3)),
            Message(.text("This one. Ridge loop, about 18k, mostly mud."), fromMe: false, date: ago(60 * 3)),
            Message(.voice(url: audio("msg_maya_voice")!, duration: 9.1, levels: Waveform.seeded("maya-msg", count: 40)), fromMe: false, date: ago(6))
        ]
        maya.unread = 2

        var chloe = Conversation(id: "chloe", profile: profile("chloe"), messages: [], matchedAt: ago(60 * 50))
        chloe.messages = [
            Message(.text("Your Tuesday dawn slot overlaps with mine. Suspicious."), fromMe: false, date: ago(60 * 49)),
            Message(.text("Canal club? I think I've seen you do strides by the bridge."), fromMe: true, date: ago(60 * 48)),
            Message(.voice(url: audio("msg_chloe_voice")!, duration: 5.6, levels: Waveform.seeded("chloe-msg", count: 40)), fromMe: false, date: ago(60 * 46)),
            Message(.text("Green footbridge, then 👟"), fromMe: true, date: ago(60 * 45), state: .read, reaction: "🔥")
        ]

        var leo = Conversation(id: "leo", profile: profile("leo"), messages: [], matchedAt: ago(60 * 4))
        leo.messages = [
            Message(.text("OK I have to ask. Do you actually know how drafting works?"), fromMe: false, date: ago(60 * 3.5)),
            Message(.text("I've been waiting my whole life for someone to ask"), fromMe: false, date: ago(60 * 3.5))
        ]
        leo.unread = 2

        var sam = Conversation(id: "sam", profile: profile("sam"), messages: [], matchedAt: ago(60 * 80))
        sam.messages = [
            Message(.text("Bench day, apparently 😂 that was terrible, I loved it"), fromMe: true, date: ago(60 * 79)),
            Message(.text("I have 40 more. Rest between sets."), fromMe: false, date: ago(60 * 78)),
            Message(.file(name: "Sam — 4 week strength block.pdf", size: 482_000, url: nil), fromMe: false, date: ago(60 * 70)),
            Message(.text("That's the plan I mentioned, if you want to try the first week together"), fromMe: false, date: ago(60 * 70)),
            Message(.text("Bring chalk 💪"), fromMe: true, date: ago(60 * 68))
        ]

        let fresh = Conversation(id: "noah", profile: profile("noah"), messages: [], matchedAt: ago(40))

        return [maya, leo, chloe, sam, fresh]
    }
}

/// Deterministic pseudo-random waveform so mock voice notes look distinct and stable.
enum Waveform {
    static func seeded(_ seed: String, count: Int) -> [Float] {
        var h: UInt64 = 1469598103934665603
        for b in seed.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return (0..<count).map { i in
            h = h &* 6364136223846793005 &+ 1442695040888963407
            let r = Float((h >> 33) % 1000) / 1000
            let envelope = sin(Float(i) / Float(count) * .pi) * 0.55 + 0.45
            return max(0.12, min(1, r * envelope + 0.1))
        }
    }
}

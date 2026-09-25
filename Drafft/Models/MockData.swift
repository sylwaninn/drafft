import Foundation

/// Synthetic demo content. Every person, photo, voice and conversation here is a placeholder.
enum MockData {
    static func audio(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "m4a")
    }

    static let me = Profile(
        id: "me",
        name: "Alex",
        age: 31,
        pronouns: "he/him",
        neighborhood: "Oberkampf",
        distanceKm: 0,
        portrait: "portrait_me",
        photos: ["sport_groupnight", "sport_bike", "sport_hike"],
        sports: [
            .init(sport: .running, perWeek: 3),
            .init(sport: .cycling, perWeek: 1),
            .init(sport: .hiking, perWeek: 1)
        ],
            voiceIntro: nil,
        voiceDuration: 0,
        icebreaker: .joke(setup: "Why did the runner bring a map to the date?", punchline: "Didn't want to lose the pace of the conversation."),
        favoriteSpot: "Canal Saint-Martin loop",
        bio: "Weekday dawn runner, weekend long rides. I plan routes that end at good coffee.",
        goal: "Paris Half under 1:35"
    )

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
            id: "ines", name: "Anne-Charlotte", age: 27, pronouns: "she/her", neighborhood: "Canal de l'Ourcq", distanceKm: 3.8, portrait: "portrait_ines", photos: ["sport_swim", "sport_yogasunset", "sport_yoga"],
            sports: [.init(sport: .swimming, perWeek: 3), .init(sport: .yoga, perWeek: 1), .init(sport: .running, perWeek: 1)],
            voiceIntro: "intro_ines",
            voiceDuration: 10.7,
            icebreaker: .hotTake("Pools are better than the sea. Chlorine is a personality."),
            favoriteSpot: "Piscine Joséphine Baker",
            bio: "Architect by day, lane 4 by dawn. Early dates only, I'm asleep by ten.",
            goal: "Swim across Lake Annecy",
            interest: .alreadyLikes
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
        ),
        Profile(
            id: "aya", name: "Aya", age: 28, pronouns: "she/her", neighborhood: "Batignolles", distanceKm: 4.1, portrait: "portrait_aya", photos: ["sport_tennis", "sport_clay", "sport_abs"],
            sports: [.init(sport: .padel, perWeek: 2), .init(sport: .tennis, perWeek: 1), .init(sport: .yoga, perWeek: 1)],
            voiceIntro: "intro_aya",
            voiceDuration: 9.0,
            icebreaker: .joke(setup: "Why are padel players great partners?", punchline: "They always use the walls to bounce back."),
            favoriteSpot: "Padel courts at Porte d'Auteuil",
            bio: "Friendly off court. Not on it. Looking for a doubles partner with good hands.",
            goal: "Win the club tournament",
            interest: .likesBackLater
        ),
        Profile(
            id: "jonas", name: "Jean-François", age: 35, pronouns: "he/him", neighborhood: "Nation", distanceKm: 2.9, portrait: "portrait_jonas", photos: ["sport_track", "sport_lacing", "sport_stepup"],
            sports: [.init(sport: .running, perWeek: 4), .init(sport: .cycling, perWeek: 1)],
            voiceIntro: "intro_jonas",
            voiceDuration: 9.6,
            icebreaker: .guess(question: "How many fountains in the Bois de Vincennes do I know by heart?",
                               options: ["6", "14", "All of them, obviously"], answer: 1),
            favoriteSpot: "Bois de Vincennes loop",
            bio: "Teacher. Wednesday track, easy miles the rest. Knows every fountain in Vincennes.",
            goal: "Sub-17 5k",
            interest: .alreadyLikes
        ),
        Profile(
            id: "zoe", name: "Marie-Guillemette", age: 26, pronouns: "she/her", neighborhood: "Pigalle", distanceKm: 3.3, portrait: "portrait_zoe", photos: ["sport_rack", "sport_abs", "sport_stepup"],
            sports: [.init(sport: .strength, perWeek: 2), .init(sport: .yoga, perWeek: 1), .init(sport: .running, perWeek: 1)],
            voiceIntro: "intro_zoe",
            voiceDuration: 9.4,
            icebreaker: .thisOrThat(question: "Be honest:", options: ["Leg day", "Arm day"], pick: 0),
            favoriteSpot: "Studio on rue des Martyrs",
            bio: "Pilates teacher, secret powerlifter. I'll judge your posture, lovingly.",
            goal: "100 kg squat",
            interest: .likesBackLater
        ),
        Profile(
            id: "nina", name: "Nina", age: 30, pronouns: "she/her", neighborhood: "Parc Montsouris", distanceKm: 4.6, portrait: "portrait_nina", photos: ["sport_yogasunset", "sport_trail", "sport_yoga"],
            sports: [.init(sport: .running, perWeek: 3), .init(sport: .yoga, perWeek: 1)],
            voiceIntro: "intro_nina",
            voiceDuration: 9.1,
            icebreaker: .twoTruths(statements: [
                "I've done 100 sun salutations in a row.",
                "I once ran a half marathon by accident.",
                "I've never seen a sunrise I didn't like."
            ], lieIndex: 0),
            favoriteSpot: "Parc Montsouris at 6am",
            bio: "Sunrise runs, evening yoga. Morning people, this is your sign.",
            goal: "First half marathon, on purpose this time",
            interest: .alreadyLikes
        ),
        Profile(
            id: "tom", name: "Tom", age: 33, pronouns: "he/him", neighborhood: "Vincennes", distanceKm: 6.0, portrait: "portrait_tom", photos: ["sport_bike", "sport_hike", "sport_peloton"],
            sports: [.init(sport: .cycling, perWeek: 2), .init(sport: .hiking, perWeek: 1)],
            voiceIntro: "intro_tom",
            voiceDuration: 4.9,
            icebreaker: .joke(setup: "My bike can't stand up on its own.", punchline: "It's two-tired. I'll see myself out."),
            favoriteSpot: "Gravel roads past Vincennes",
            bio: "Bike commuter, gravel on weekends, hikes that end with a sandwich and a view.",
            goal: "Paris–Roubaix sportive"
        ),
        Profile(
            id: "lucas", name: "Maximilien-Alexandre", age: 29, pronouns: "he/him", neighborhood: "Pantin", distanceKm: 5.5, portrait: "portrait_lucas", photos: ["sport_boulder", "sport_cliff", "sport_pullup"],
            sports: [.init(sport: .climbing, perWeek: 3), .init(sport: .strength, perWeek: 1)],
            voiceIntro: "intro_lucas",
            voiceDuration: 7.6,
            icebreaker: .twoTruths(statements: [
                "I cook a four-course dinner after every send.",
                "I climbed in Fontainebleau every weekend last year.",
                "I've never used chalk."
            ], lieIndex: 2),
            favoriteSpot: "Block'Out Pantin",
            bio: "Chef who climbs to work off the tasting menu. Great belayer, better cheerleader.",
            goal: "Fontainebleau 7b",
            interest: .alreadyLikes
        )
    ]

    /// Profiles in the swipe deck (people you haven't matched with yet).
    static var deck: [Profile] {
        var aya = profile("aya")
        aya.superLikedMe = true
        aya.superLikeNote = "Your Sunday long runs look like my pace. Montsouris loop this weekend?"
        // A long name with a super like and no note, to check the identity line holds up.
        var ines = profile("ines")
        ines.superLikedMe = true
        // Super likes jump the queue.
        return [aya, ines] + ["nina", "tom", "lucas", "zoe", "jonas"].map(profile)
    }

    /// Next occurrence of a weekday (0 = Monday) at a given hour, for demo sessions.
    static func next(weekday: Int, hour: Int, minute: Int = 0) -> Date {
        let cal = Calendar.current
        let target = (weekday + 1) % 7 + 1 // Calendar: 1 = Sunday
        let base = cal.nextDate(after: .now, matching: DateComponents(weekday: target), matchingPolicy: .nextTime) ?? .now
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }

    static func profile(_ id: String) -> Profile { profiles.first { $0.id == id }! }

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
        // Maya offers three times: your turn to pick.
        maya.messages.append(Message(.text("Also… trail session this weekend? Pick one 👇"), fromMe: false, date: ago(4)))
        maya.messages.append(Message(.session(SessionProposal(
            sport: .trail,
            options: [Self.next(weekday: 5, hour: 9), Self.next(weekday: 6, hour: 8, minute: 30), Self.next(weekday: 6, hour: 10)],
            title: "Muddy loop in Fontainebleau?", note: "")), fromMe: false, date: ago(4)))
        maya.unread = 4

        var chloe = Conversation(id: "chloe", profile: profile("chloe"), messages: [], matchedAt: ago(60 * 50))
        chloe.messages = [
            Message(.text("Your Tuesday dawn slot overlaps with mine. Suspicious."), fromMe: false, date: ago(60 * 49)),
            Message(.text("Canal club? I think I've seen you do strides by the bridge."), fromMe: true, date: ago(60 * 48)),
            Message(.session(SessionProposal(sport: .running, options: [Self.next(weekday: 1, hour: 7)], chosen: Self.next(weekday: 1, hour: 7), title: "Easy 8k along the canal, then coffee?", note: "Meet at the green footbridge.", status: .accepted)), fromMe: true, date: ago(60 * 47)),
            Message(.voice(url: audio("msg_chloe_voice")!, duration: 5.6, levels: Waveform.seeded("chloe-msg", count: 40)), fromMe: false, date: ago(60 * 46)),
            Message(.text("See you at 7 by the green footbridge 👟"), fromMe: true, date: ago(60 * 45), state: .read, reaction: "🔥")
        ]

        var leo = Conversation(id: "leo", profile: profile("leo"), messages: [], matchedAt: ago(60 * 4))
        leo.messages = [
            Message(.text("OK I have to ask. Do you actually know how drafting works?"), fromMe: false, date: ago(60 * 3.5)),
            Message(.text("I've been waiting my whole life for someone to ask"), fromMe: false, date: ago(60 * 3.5))
        ]
        // Your invite to Alexandre-Maxime, waiting for him to pick.
        leo.messages.append(Message(.session(SessionProposal(
            sport: .cycling,
            options: [Self.next(weekday: 5, hour: 7), Self.next(weekday: 6, hour: 7, minute: 30)],
            title: "Longchamp laps at sunrise?", note: "")), fromMe: true, date: ago(60 * 3), state: .delivered))
        leo.unread = 2

        var sam = Conversation(id: "sam", profile: profile("sam"), messages: [], matchedAt: ago(60 * 80))
        sam.messages = [
            Message(.text("Bench day, apparently 😂 that was terrible, I loved it"), fromMe: true, date: ago(60 * 79)),
            Message(.text("I have 40 more. Rest between sets."), fromMe: false, date: ago(60 * 78)),
            Message(.file(name: "Sam — 4 week strength block.pdf", size: 482_000, url: nil), fromMe: false, date: ago(60 * 70)),
            Message(.text("That's the plan I mentioned, if you want to try the first week together"), fromMe: false, date: ago(60 * 70)),
            Message(.session(SessionProposal(
                sport: .strength,
                options: [Self.next(weekday: 3, hour: 19)], chosen: Self.next(weekday: 3, hour: 19),
                title: "Leg day, I'll spot you?", note: "", status: .accepted)), fromMe: false, date: ago(60 * 69)),
            Message(.text("Thursday it is. Bring chalk 💪"), fromMe: true, date: ago(60 * 68))
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

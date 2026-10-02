import Foundation

/// Every sport in Drafft, in one place. Pickers (sign-up, Edit profile, Filters) all read this
/// list, and each sport has its own symbol (never shared with another sport).
enum Sport: String, CaseIterable, Identifiable, Hashable, Codable {
    // Endurance
    case running, trail, walking, hiking, cycling, spinning, mountainBiking
    case runClub, ultra, gravel, obstacleRace, stairClimbing
    case swimming, openWater, triathlon, rowing
    // Water & board
    case surfing, sailing, skateboarding, kitesurf, wingFoil, paddleBoard, kayak
    // Snow
    case skiing, crossCountrySki, snowboarding, skiTouring, iceSkating
    // Gym & strength
    case hyrox, strength, functional, crossfit, hiit, calisthenics, jumpRope, parkour
    // Mind & body
    case yoga, hotYoga, pilates, reformer, barre, mobility, taichi, dance, gymnastics
    // Combat
    case boxing, kickboxing, martialArts, bjj, fencing
    // Racket
    case padel, tennis, beachTennis, badminton, squash, tableTennis, pickleball
    // Team
    case football, basketball, volleyball, beachVolley, rugby, handball, hockey, ultimate, spikeball
    // Outdoor & precision
    case climbing, bouldering, golf, equestrian, archery

    var id: String { rawValue }

    /// The sport as a code for an event (`mountain_biking`): the id is camelCase, which isn't one.
    var telemetryID: String { rawValue.snakeCased }

    private struct Info { let name: String; let symbol: String; let verbing: String; let poster: String }

    private var info: Info {
        switch self {
        case .running: Info(name: L("Running"), symbol: "steps-outline", verbing: L("running"), poster: "sport_sunsetrun")
        case .trail: Info(name: L("Trail"), symbol: "landscape-2-outline", verbing: L("trail running"), poster: "sport_trail")
        case .walking: Info(name: L("Walking"), symbol: "walking", verbing: L("walking"), poster: "sport_hike")
        case .hiking: Info(name: L("Hiking"), symbol: "hiking", verbing: L("hiking"), poster: "sport_hike")
        case .cycling: Info(name: L("Cycling"), symbol: "bicycling", verbing: L("cycling"), poster: "sport_peloton")
        case .spinning: Info(name: L("Indoor cycling"), symbol: "directions-bike", verbing: L("spinning"), poster: "sport_peloton")
        case .mountainBiking: Info(name: L("Mountain biking"), symbol: "pedal-bike-outline", verbing: L("mountain biking"),
                                   poster: "sport_bike")
        case .swimming: Info(name: L("Swimming"), symbol: "swimming", verbing: L("swimming"), poster: "sport_swim")
        case .openWater: Info(name: L("Open water"), symbol: "water-sun", verbing: L("open-water swimming"), poster: "sport_swim")
        case .triathlon: Info(name: L("Triathlon"), symbol: "medal-ribbons-star", verbing: L("training"), poster: "sport_swim")
        case .rowing: Info(name: L("Rowing"), symbol: "rowing", verbing: L("rowing"), poster: "sport_ropes")
        case .surfing: Info(name: L("Surfing"), symbol: "surfing", verbing: L("surfing"), poster: "sport_swim")
        case .sailing: Info(name: L("Sailing"), symbol: "sailing-outline", verbing: L("sailing"), poster: "sport_swim")
        case .skateboarding: Info(name: L("Skateboarding"), symbol: "skateboarding", verbing: L("skating"), poster: "sport_groupnight")
        case .skiing: Info(name: L("Skiing"), symbol: "downhill-skiing-outline", verbing: L("skiing"), poster: "sport_hike")
        case .crossCountrySki: Info(name: L("Cross-country skiing"), symbol: "nordic-walking", verbing: L("cross-country skiing"),
                                    poster: "sport_hike")
        case .snowboarding: Info(name: L("Snowboarding"), symbol: "snowboarding", verbing: L("snowboarding"), poster: "sport_hike")
        case .strength: Info(name: L("Strength"), symbol: "dumbbell-large", verbing: L("lifting"), poster: "sport_barbell")
        case .functional: Info(name: L("Functional training"), symbol: "weight-outline", verbing: L("training"), poster: "sport_ropes")
        case .crossfit: Info(name: L("CrossFit"), symbol: "fitness-center", verbing: L("at CrossFit"), poster: "sport_ropes")
        case .hiit: Info(name: L("HIIT"), symbol: "heart-pulse", verbing: L("doing HIIT"), poster: "sport_abs")
        case .calisthenics: Info(name: L("Calisthenics"), symbol: "accessibility-new", verbing: L("doing calisthenics"),
                                 poster: "sport_pullup")
        case .jumpRope: Info(name: L("Jump rope"), symbol: "jump-rope", verbing: L("skipping"), poster: "sport_abs")
        case .yoga: Info(name: L("Yoga"), symbol: "meditation", verbing: L("doing yoga"), poster: "sport_yogasunset")
        case .pilates: Info(name: L("Pilates"), symbol: "stretching", verbing: L("doing Pilates"), poster: "sport_yoga")
        case .barre: Info(name: L("Barre"), symbol: "body-shape", verbing: L("at barre"), poster: "sport_yoga")
        case .mobility: Info(name: L("Mobility"), symbol: "accessibility", verbing: L("stretching"), poster: "sport_yoga")
        case .taichi: Info(name: L("Tai chi"), symbol: "taichi", verbing: L("doing tai chi"), poster: "sport_yogasunset")
        case .dance: Info(name: L("Dance"), symbol: "music-notes", verbing: L("dancing"), poster: "sport_groupnight")
        case .gymnastics: Info(name: L("Gymnastics"), symbol: "sports-gymnastics", verbing: L("doing gymnastics"), poster: "sport_abs")
        case .boxing: Info(name: L("Boxing"), symbol: "sports-mma-outline", verbing: L("boxing"), poster: "sport_barbell")
        case .kickboxing: Info(name: L("Kickboxing"), symbol: "sports-martial-arts", verbing: L("kickboxing"), poster: "sport_barbell")
        case .martialArts: Info(name: L("Martial arts"), symbol: "martial-arts", verbing: L("training"), poster: "sport_barbell")
        case .fencing: Info(name: L("Fencing"), symbol: "fencing", verbing: L("fencing"), poster: "sport_groupnight")
        case .padel: Info(name: L("Padel"), symbol: "padel", verbing: L("playing padel"), poster: "sport_tennis")
        case .tennis: Info(name: L("Tennis"), symbol: "tennis", verbing: L("playing tennis"), poster: "sport_clay")
        case .badminton: Info(name: L("Badminton"), symbol: "badminton", verbing: L("playing badminton"), poster: "sport_tennis")
        case .squash: Info(name: L("Squash"), symbol: "sports-tennis-outline", verbing: L("playing squash"), poster: "sport_tennis")
        case .tableTennis: Info(name: L("Table tennis"), symbol: "table-tennis", verbing: L("playing ping-pong"), poster: "sport_tennis")
        case .pickleball: Info(name: L("Pickleball"), symbol: "pickleball", verbing: L("playing pickleball"), poster: "sport_clay")
        case .football: Info(name: L("Football"), symbol: "football", verbing: L("playing football"), poster: "sport_groupnight")
        case .basketball: Info(name: L("Basketball"), symbol: "basketball", verbing: L("playing basketball"), poster: "sport_groupnight")
        case .volleyball: Info(name: L("Volleyball"), symbol: "volleyball", verbing: L("playing volleyball"), poster: "sport_groupnight")
        case .rugby: Info(name: L("Rugby"), symbol: "rugby", verbing: L("playing rugby"), poster: "sport_groupnight")
        case .handball: Info(name: L("Handball"), symbol: "sports-handball", verbing: L("playing handball"), poster: "sport_groupnight")
        case .hockey: Info(name: L("Hockey"), symbol: "sports-hockey", verbing: L("playing hockey"), poster: "sport_groupnight")
        case .climbing: Info(name: L("Climbing"), symbol: "carabiner", verbing: L("climbing"), poster: "sport_boulder")
        case .golf: Info(name: L("Golf"), symbol: "golf", verbing: L("golfing"), poster: "sport_hike")
        case .equestrian: Info(name: L("Horse riding"), symbol: "horseshoe", verbing: L("riding"), poster: "sport_hike")
        case .archery: Info(name: L("Archery"), symbol: "target", verbing: L("at the range"), poster: "sport_hike")
        // Trending
        case .hyrox: Info(name: L("Hyrox"), symbol: "stopwatch", verbing: L("training for Hyrox"), poster: "sport_ropes")
        case .runClub: Info(name: L("Run club"), symbol: "users-group-rounded", verbing: L("at run club"), poster: "sport_groupnight")
        case .ultra: Info(name: L("Ultra running"), symbol: "infinite", verbing: L("running long"), poster: "sport_trail")
        case .gravel: Info(name: L("Gravel"), symbol: "routing", verbing: L("riding gravel"), poster: "sport_bike")
        case .obstacleRace: Info(name: L("Obstacle racing"), symbol: "fence", verbing: L("racing"), poster: "sport_ropes")
        case .stairClimbing: Info(name: L("Stepper"), symbol: "stairs-2", verbing: L("on the stepper"), poster: "sport_stairs")
        case .kitesurf: Info(name: L("Kitesurf"), symbol: "kitesurfing-outline", verbing: L("kiting"), poster: "sport_swim")
        case .wingFoil: Info(name: L("Wing foil"), symbol: "wind", verbing: L("foiling"), poster: "sport_swim")
        case .paddleBoard: Info(name: L("Paddleboard"), symbol: "water", verbing: L("paddling"), poster: "sport_swim")
        case .kayak: Info(name: L("Kayak"), symbol: "kayaking", verbing: L("kayaking"), poster: "sport_swim")
        case .skiTouring: Info(name: L("Ski touring"), symbol: "snowflake", verbing: L("ski touring"), poster: "sport_hike")
        case .iceSkating: Info(name: L("Ice skating"), symbol: "ice-skating-outline", verbing: L("skating"), poster: "sport_groupnight")
        case .parkour: Info(name: L("Parkour"), symbol: "sprint", verbing: L("doing parkour"), poster: "sport_stairs")
        case .hotYoga: Info(name: L("Hot yoga"), symbol: "temperature", verbing: L("at hot yoga"), poster: "sport_yoga")
        case .reformer: Info(name: L("Reformer Pilates"), symbol: "physical-therapy", verbing: L("on the reformer"), poster: "sport_yoga")
        case .bjj: Info(name: L("Jiu-jitsu"), symbol: "sports-kabaddi", verbing: L("rolling"), poster: "sport_barbell")
        case .beachTennis: Info(name: L("Beach tennis"), symbol: "sun", verbing: L("playing beach tennis"), poster: "sport_tennis")
        case .beachVolley: Info(name: L("Beach volley"), symbol: "umbrella", verbing: L("playing beach volley"), poster: "sport_groupnight")
        case .ultimate: Info(name: L("Ultimate frisbee"), symbol: "frisbee", verbing: L("playing ultimate"), poster: "sport_groupnight")
        case .spikeball: Info(name: L("Spikeball"), symbol: "spikeball", verbing: L("playing spikeball"),
                                     poster: "sport_groupnight")
        case .bouldering: Info(name: L("Bouldering"), symbol: "boulder", verbing: L("bouldering"), poster: "sport_boulder")
        }
    }

    var name: String { info.name }
    /// The name inside a sentence ("easy padel session"): lowercased in the app's language,
    /// except in German where nouns keep their capital.
    var inSentence: String {
        Localization.shared.language == .de ? name : name.lowercased(with: .app)
    }
    var symbol: String { info.symbol }
    /// "running", "on the bike"… for sentences like "you're usually out running".
    var verbing: String { info.verbing }
    /// Stock photo used as the header of a sport block (demo imagery).
    var posterImage: String { info.poster }

    /// Case- and accent-insensitive match for search fields.
    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

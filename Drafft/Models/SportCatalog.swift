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

    private struct Info { let name: String; let symbol: String; let verbing: String; let poster: String }

    private var info: Info {
        switch self {
        case .running: Info(name: L("Running"), symbol: "figure.run", verbing: L("running"), poster: "sport_sunsetrun")
        case .trail: Info(name: L("Trail"), symbol: "figure.hiking", verbing: L("trail running"), poster: "sport_trail")
        case .walking: Info(name: L("Walking"), symbol: "figure.walk", verbing: L("walking"), poster: "sport_hike")
        case .hiking: Info(name: L("Hiking"), symbol: "mountain.2", verbing: L("hiking"), poster: "sport_hike")
        case .cycling: Info(name: L("Cycling"), symbol: "figure.outdoor.cycle", verbing: L("cycling"), poster: "sport_peloton")
        case .spinning: Info(name: L("Indoor cycling"), symbol: "figure.indoor.cycle", verbing: L("spinning"), poster: "sport_peloton")
        case .mountainBiking: Info(name: L("Mountain biking"), symbol: "bicycle", verbing: L("mountain biking"), poster: "sport_bike")
        case .swimming: Info(name: L("Swimming"), symbol: "figure.pool.swim", verbing: L("swimming"), poster: "sport_swim")
        case .openWater: Info(name: L("Open water"), symbol: "figure.open.water.swim", verbing: L("open-water swimming"), poster: "sport_swim")
        case .triathlon: Info(name: L("Triathlon"), symbol: "medal", verbing: L("training"), poster: "sport_swim")
        case .rowing: Info(name: L("Rowing"), symbol: "figure.rower", verbing: L("rowing"), poster: "sport_ropes")
        case .surfing: Info(name: L("Surfing"), symbol: "figure.surfing", verbing: L("surfing"), poster: "sport_swim")
        case .sailing: Info(name: L("Sailing"), symbol: "sailboat.fill", verbing: L("sailing"), poster: "sport_swim")
        case .skateboarding: Info(name: L("Skateboarding"), symbol: "figure.skateboarding", verbing: L("skating"), poster: "sport_groupnight")
        case .skiing: Info(name: L("Skiing"), symbol: "figure.skiing.downhill", verbing: L("skiing"), poster: "sport_hike")
        case .crossCountrySki: Info(name: L("Cross-country skiing"), symbol: "figure.skiing.crosscountry", verbing: L("cross-country skiing"), poster: "sport_hike")
        case .snowboarding: Info(name: L("Snowboarding"), symbol: "figure.snowboarding", verbing: L("snowboarding"), poster: "sport_hike")
        case .strength: Info(name: L("Strength"), symbol: "figure.strengthtraining.traditional", verbing: L("lifting"), poster: "sport_barbell")
        case .functional: Info(name: L("Functional training"), symbol: "figure.strengthtraining.functional", verbing: L("training"), poster: "sport_ropes")
        case .crossfit: Info(name: L("CrossFit"), symbol: "figure.cross.training", verbing: L("at CrossFit"), poster: "sport_ropes")
        case .hiit: Info(name: L("HIIT"), symbol: "figure.highintensity.intervaltraining", verbing: L("doing HIIT"), poster: "sport_abs")
        case .calisthenics: Info(name: L("Calisthenics"), symbol: "figure.core.training", verbing: L("doing calisthenics"), poster: "sport_pullup")
        case .jumpRope: Info(name: L("Jump rope"), symbol: "figure.jumprope", verbing: L("skipping"), poster: "sport_abs")
        case .yoga: Info(name: L("Yoga"), symbol: "figure.yoga", verbing: L("doing yoga"), poster: "sport_yogasunset")
        case .pilates: Info(name: L("Pilates"), symbol: "figure.pilates", verbing: L("doing Pilates"), poster: "sport_yoga")
        case .barre: Info(name: L("Barre"), symbol: "figure.barre", verbing: L("at barre"), poster: "sport_yoga")
        case .mobility: Info(name: L("Mobility"), symbol: "figure.mind.and.body", verbing: L("stretching"), poster: "sport_yoga")
        case .taichi: Info(name: L("Tai chi"), symbol: "figure.taichi", verbing: L("doing tai chi"), poster: "sport_yogasunset")
        case .dance: Info(name: L("Dance"), symbol: "figure.dance", verbing: L("dancing"), poster: "sport_groupnight")
        case .gymnastics: Info(name: L("Gymnastics"), symbol: "figure.gymnastics", verbing: L("doing gymnastics"), poster: "sport_abs")
        case .boxing: Info(name: L("Boxing"), symbol: "figure.boxing", verbing: L("boxing"), poster: "sport_barbell")
        case .kickboxing: Info(name: L("Kickboxing"), symbol: "figure.kickboxing", verbing: L("kickboxing"), poster: "sport_barbell")
        case .martialArts: Info(name: L("Martial arts"), symbol: "figure.martial.arts", verbing: L("training"), poster: "sport_barbell")
        case .fencing: Info(name: L("Fencing"), symbol: "figure.fencing", verbing: L("fencing"), poster: "sport_groupnight")
        case .padel: Info(name: L("Padel"), symbol: "figure.racquetball", verbing: L("playing padel"), poster: "sport_tennis")
        case .tennis: Info(name: L("Tennis"), symbol: "figure.tennis", verbing: L("playing tennis"), poster: "sport_clay")
        case .badminton: Info(name: L("Badminton"), symbol: "figure.badminton", verbing: L("playing badminton"), poster: "sport_tennis")
        case .squash: Info(name: L("Squash"), symbol: "figure.squash", verbing: L("playing squash"), poster: "sport_tennis")
        case .tableTennis: Info(name: L("Table tennis"), symbol: "figure.table.tennis", verbing: L("playing ping-pong"), poster: "sport_tennis")
        case .pickleball: Info(name: L("Pickleball"), symbol: "figure.pickleball", verbing: L("playing pickleball"), poster: "sport_clay")
        case .football: Info(name: L("Football"), symbol: "figure.soccer", verbing: L("playing football"), poster: "sport_groupnight")
        case .basketball: Info(name: L("Basketball"), symbol: "figure.basketball", verbing: L("playing basketball"), poster: "sport_groupnight")
        case .volleyball: Info(name: L("Volleyball"), symbol: "figure.volleyball", verbing: L("playing volleyball"), poster: "sport_groupnight")
        case .rugby: Info(name: L("Rugby"), symbol: "figure.rugby", verbing: L("playing rugby"), poster: "sport_groupnight")
        case .handball: Info(name: L("Handball"), symbol: "figure.handball", verbing: L("playing handball"), poster: "sport_groupnight")
        case .hockey: Info(name: L("Hockey"), symbol: "figure.hockey", verbing: L("playing hockey"), poster: "sport_groupnight")
        case .climbing: Info(name: L("Climbing"), symbol: "figure.climbing", verbing: L("climbing"), poster: "sport_boulder")
        case .golf: Info(name: L("Golf"), symbol: "figure.golf", verbing: L("golfing"), poster: "sport_hike")
        case .equestrian: Info(name: L("Horse riding"), symbol: "figure.equestrian.sports", verbing: L("riding"), poster: "sport_hike")
        case .archery: Info(name: L("Archery"), symbol: "figure.archery", verbing: L("at the range"), poster: "sport_hike")
        // Trending
        case .hyrox: Info(name: L("Hyrox"), symbol: "stopwatch.fill", verbing: L("training for Hyrox"), poster: "sport_ropes")
        case .runClub: Info(name: L("Run club"), symbol: "figure.run.circle", verbing: L("at run club"), poster: "sport_groupnight")
        case .ultra: Info(name: L("Ultra running"), symbol: "figure.run.square.stack", verbing: L("running long"), poster: "sport_trail")
        case .gravel: Info(name: L("Gravel"), symbol: "road.lanes", verbing: L("riding gravel"), poster: "sport_bike")
        case .obstacleRace: Info(name: L("Obstacle racing"), symbol: "flag.2.crossed.fill", verbing: L("racing"), poster: "sport_ropes")
        case .stairClimbing: Info(name: L("Stair climbing"), symbol: "figure.stair.stepper", verbing: L("climbing stairs"), poster: "sport_stairs")
        case .kitesurf: Info(name: L("Kitesurf"), symbol: "wind", verbing: L("kiting"), poster: "sport_swim")
        case .wingFoil: Info(name: L("Wing foil"), symbol: "water.waves", verbing: L("foiling"), poster: "sport_swim")
        case .paddleBoard: Info(name: L("Paddleboard"), symbol: "figure.water.fitness", verbing: L("paddling"), poster: "sport_swim")
        case .kayak: Info(name: L("Kayak"), symbol: "oar.2.crossed", verbing: L("kayaking"), poster: "sport_swim")
        case .skiTouring: Info(name: L("Ski touring"), symbol: "snowflake", verbing: L("ski touring"), poster: "sport_hike")
        case .iceSkating: Info(name: L("Ice skating"), symbol: "figure.skating", verbing: L("skating"), poster: "sport_groupnight")
        case .parkour: Info(name: L("Parkour"), symbol: "figure.stairs", verbing: L("doing parkour"), poster: "sport_stairs")
        case .hotYoga: Info(name: L("Hot yoga"), symbol: "thermometer.sun.fill", verbing: L("at hot yoga"), poster: "sport_yoga")
        case .reformer: Info(name: L("Reformer Pilates"), symbol: "figure.flexibility", verbing: L("on the reformer"), poster: "sport_yoga")
        case .bjj: Info(name: L("Jiu-jitsu"), symbol: "figure.wrestling", verbing: L("rolling"), poster: "sport_barbell")
        case .beachTennis: Info(name: L("Beach tennis"), symbol: "sun.max.fill", verbing: L("playing beach tennis"), poster: "sport_tennis")
        case .beachVolley: Info(name: L("Beach volley"), symbol: "beach.umbrella", verbing: L("playing beach volley"), poster: "sport_groupnight")
        case .ultimate: Info(name: L("Ultimate frisbee"), symbol: "figure.disc.sports", verbing: L("playing ultimate"), poster: "sport_groupnight")
        case .spikeball: Info(name: L("Spikeball"), symbol: "circle.circle", verbing: L("playing spikeball"), poster: "sport_groupnight")
        case .bouldering: Info(name: L("Bouldering"), symbol: "mountain.2.fill", verbing: L("bouldering"), poster: "sport_boulder")
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

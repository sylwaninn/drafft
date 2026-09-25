import Foundation

struct SportEntry: Hashable, Identifiable {
    var sport: Sport
    /// Sessions per week, set in onboarding and Edit profile.
    var perWeek: Int
    var id: Sport { sport }

    init(sport: Sport, perWeek: Int = 1) {
        self.sport = sport
        self.perWeek = perWeek
    }

    var perWeekText: String { perWeek >= 7 ? L("Every day") : L("\(perWeek)× a week") }
}

enum Weekday {
    static let short = ["M", "T", "W", "T", "F", "S", "S"]
    static let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    static let abbr = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
}

/// The interactive prompt on a profile: something a viewer can play with, then reply to.
enum Icebreaker: Hashable {
    /// Two truths and a lie: viewer guesses which one is invented.
    case twoTruths(statements: [String], lieIndex: Int)
    /// Setup and punchline; the punchline is revealed on tap.
    case joke(setup: String, punchline: String)
    /// A strong opinion the viewer agrees or disagrees with.
    case hotTake(String)
    /// Two options: the viewer picks one, then sees which one they picked.
    case thisOrThat(question: String, options: [String], pick: Int)
    /// A question about them with three answers, one right: the viewer guesses.
    case guess(question: String, options: [String], answer: Int)

    enum Kind: String, CaseIterable, Identifiable {
        case twoTruths, joke, hotTake, thisOrThat, guess
        var id: String { rawValue }
        var title: String {
            switch self {
            case .twoTruths: L("Two truths, one lie")
            case .joke: L("Bad joke")
            case .hotTake: L("Hot take")
            case .thisOrThat: L("This or that")
            case .guess: L("Guess about me")
            }
        }
        var detail: String {
            switch self {
            case .twoTruths: L("They spot the lie")
            case .joke: L("They tap for the punchline")
            case .hotTake: L("They agree or disagree")
            case .thisOrThat: L("They pick a side, then see yours")
            case .guess: L("They guess the right answer")
            }
        }
        var symbol: String {
            switch self {
            case .twoTruths: "eyes"
            case .joke: "theatermasks.fill"
            case .hotTake: "flame.fill"
            case .thisOrThat: "arrow.left.arrow.right"
            case .guess: "questionmark.bubble.fill"
            }
        }
        /// Starting content when switching to this kind in the editor.
        var blank: Icebreaker {
            switch self {
            case .twoTruths: .twoTruths(statements: ["", "", ""], lieIndex: -1)
            case .joke: .joke(setup: "", punchline: "")
            case .hotTake: .hotTake("")
            case .thisOrThat: .thisOrThat(question: "", options: ["", ""], pick: -1)
            case .guess: .guess(question: "", options: ["", "", ""], answer: -1)
            }
        }
    }

    var kind: Kind {
        switch self {
        case .twoTruths: .twoTruths
        case .joke: .joke
        case .hotTake: .hotTake
        case .thisOrThat: .thisOrThat
        case .guess: .guess
        }
    }

    /// Every field filled in.
    /// Nothing written yet (a skipped prompt): hidden on the profile, allowed when saving.
    var isBlank: Bool {
        func empty(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespaces).isEmpty }
        return switch self {
        case let .twoTruths(st, _): st.allSatisfy(empty)
        case let .joke(a, b): empty(a) && empty(b)
        case let .hotTake(t): empty(t)
        case let .thisOrThat(q, o, _): empty(q) && o.allSatisfy(empty)
        case let .guess(q, o, _): empty(q) && o.allSatisfy(empty)
        }
    }

    var isComplete: Bool {
        func ok(_ s: String) -> Bool { !s.trimmingCharacters(in: .whitespaces).isEmpty }
        return switch self {
        // The choice (lie, pick, right answer) starts at -1: nothing chosen for the person.
        case let .twoTruths(st, lie): st.allSatisfy(ok) && st.indices.contains(lie)
        case let .joke(a, b): ok(a) && ok(b)
        case let .hotTake(t): ok(t)
        case let .thisOrThat(q, o, pick): ok(q) && o.allSatisfy(ok) && o.indices.contains(pick)
        case let .guess(q, o, answer): ok(q) && o.allSatisfy(ok) && o.indices.contains(answer)
        }
    }
}

struct Profile: Identifiable, Hashable {
    let id: String
    var name: String
    var age: Int
    var pronouns: String?
    /// Their own answer at sign-up (the server's `gender`). Nil on demo profiles: see `audience(of:)`.
    var gender: DiscoverFilters.Audience?
    var neighborhood: String
    var distanceKm: Double
    var portrait: String
    var photos: [String]
    var sports: [SportEntry]
    var voiceIntro: String?
    var voiceDuration: TimeInterval
    var icebreaker: Icebreaker
    var favoriteSpot: String
    var bio: String
    var goal: String
    /// Demo matching logic: whether this person already liked you, or will like you back shortly.
    var interest: Interest = .none
    /// They super liked you: their card comes first in your deck, marked in red, with their note.
    var superLikedMe = false
    var superLikeNote: String?
    /// Set when the user edits their own profile (demo data otherwise comes from MockData.extras).
    var vitalsOverride: Vitals?
    var promptsOverride: [ProfilePrompt]?

    enum Interest: Hashable { case none, alreadyLikes, likesBackLater }

    var firstName: String { name }
    var allPhotos: [String] { [portrait] + photos }
}

// MARK: - Sessions

struct SessionProposal: Hashable, Identifiable {
    let id = UUID()
    var sport: Sport
    /// Proposed day-and-time options (1 to 3). The other person picks one or suggests others.
    var options: [Date]
    /// The option both agreed on, once accepted.
    var chosen: Date?
    /// Optional headline for the invite, e.g. "Cool morning run in Parc de la Tête d'Or?".
    var title: String = ""
    var note: String
    /// Plan details picked as toggles ("Easy pace", "Coffee after"…), separate from the free note.
    var tags: [String] = []
    /// Set when one of you introduces the other to a sport they don't do yet.
    var discovery: Discovery?
    var status: Status = .pending

    /// pending: waiting for a pick; countered: replaced by a newer proposal with other times.
    enum Status: Hashable { case pending, accepted, declined, countered }

    /// The agreed time, or the first option while it's still being decided.
    var date: Date { chosen ?? options.first ?? .now }
    enum Discovery: Hashable { case iTeach, theyTeach }

    var displayTitle: String { title.isEmpty ? L("\(sport.name) session") : title }

    /// Title ideas per sport, shown as tappable examples.
    static func titleIdeas(for sport: Sport) -> [String] {
        switch sport {
        case .running: [L("Cool morning run in Parc de la Tête d'Or?"), L("Easy 8k along the canal, then croissants?"), L("Intervals, loser buys coffee?")]
        case .trail: [L("Muddy loop in Fontainebleau?"), L("Hill repeats and a view?"), L("Long slow trail, big brunch after?")]
        case .cycling: [L("Longchamp laps at sunrise?"), L("Gravel ride with a picnic stop?"), L("Easy spin to a café?")]
        case .swimming: [L("Early lengths at the outdoor pool?"), L("1k swim, then breakfast?"), L("Open-water dip if you dare?")]
        case .climbing: [L("Bouldering, then a beer?"), L("Project night, you spot me?"), L("Easy circuits for a first session?")]
        case .padel: [L("Doubles, loser buys drinks?"), L("Friendly match after work?"), L("Padel and a terrace?")]
        case .tennis: [L("A few sets before work?"), L("Rally, no score, just fun?"), L("Best of three, winner picks dinner?")]
        case .strength: [L("Leg day, I'll spot you?"), L("Push day then smoothies?"), L("Deadlift PR attempt, come cheer?")]
        case .yoga: [L("Sunset flow in the park?"), L("Morning stretch, slow start?"), L("Yoga then a long lunch?")]
        case .hiking: [L("Forest walk with a picnic?"), L("Day hike, sandwiches on me?"), L("Sunrise hike, worth the alarm?")]
        case .crossfit: [L("WOD together, no mercy?"), L("Partner workout, then tacos?"), L("Saturday class, you in?")]
        case .triathlon: [L("Brick session: bike then run?"), L("Swim-run by the lake?"), L("Easy aerobic day together?")]
        default: [L("\(sport.name) together, then coffee?"), L("Easy \(sport.inSentence) session to start?"),
                  L("Come try my usual \(sport.inSentence) spot?")]
        }
    }

    /// "Tuesday 30 Sep at 07:00"
    var whenText: String { L("\(dayText) at \(timeText)") }
    var dayText: String { date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(.app)) }
    var timeText: String { date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(.app)) }
}

// MARK: - Chat

enum DeliveryState: Int, Comparable, Hashable {
    case sending, sent, delivered, read
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

enum MessageContent: Hashable {
    case text(String)
    case photo(asset: String?, imageData: Data?)
    case video(url: URL, thumbnail: Data?, duration: TimeInterval)
    case voice(url: URL, duration: TimeInterval, levels: [Float])
    case file(name: String, size: Int64, url: URL?)
    case session(SessionProposal)
    case icebreakerReply(quote: String, reply: String)
    /// A like on one of their photos, carried into the match as the first message.
    case photoReply(asset: String, reply: String)
}

struct Message: Identifiable, Hashable {
    let id: UUID
    var content: MessageContent
    var fromMe: Bool
    var date: Date
    var state: DeliveryState
    var reaction: String?
    /// The message this one answers (swipe to reply, or Reply in the long-press menu).
    var replyTo: UUID?

    init(id: UUID = UUID(), _ content: MessageContent, fromMe: Bool, date: Date = .now, state: DeliveryState = .read,
         reaction: String? = nil, replyTo: UUID? = nil) {
        self.id = id
        self.replyTo = replyTo
        self.content = content
        self.fromMe = fromMe
        self.date = date
        self.state = state
        self.reaction = reaction
    }

    var previewText: String {
        switch content {
        case .text(let t): t
        case .photo: L("Photo")
        case .video: L("Video")
        case .voice(_, let d, _): L("Voice message (\(d.clock))")
        case .file(let name, _, _): name
        case .session(let s): L("Session: \(s.sport.name), \(s.date.formatted(.dateTime.weekday(.abbreviated).day().locale(.app)))")
        case .icebreakerReply(_, let reply): reply.isEmpty ? L("Liked your profile") : reply
        case .photoReply(_, let reply): reply.isEmpty ? L("Liked a photo") : reply
        }
    }
}

struct Conversation: Identifiable, Hashable {
    let id: String
    var profile: Profile
    var messages: [Message]
    var isTyping = false
    var unread: Int = 0
    /// Marked unread by hand ("Mark as unread"): a dot, no count. Cleared when the chat is opened.
    var markedUnread = false
    /// Shown as unread in the list: messages not read yet, or marked by hand.
    var isUnread: Bool { unread > 0 || markedUnread }
    var matchedAt: Date
    /// Muted chats stay in the list but leave the tab badge and use a quiet unread badge.
    var muted = false

    var lastMessage: Message? { messages.last }
}

extension TimeInterval {
    var clock: String {
        let s = Int(self.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

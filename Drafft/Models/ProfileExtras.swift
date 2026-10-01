import Foundation

/// Hinge-style profile content: quick facts ("vitals") and written prompts that can be liked one by one.
struct ProfilePrompt: Hashable, Identifiable {
    var question: String
    var answer: String
    var id: String { question }
    /// The question in the app's language. `question` stays the English library text: it's the
    /// prompt's identity (saved, compared, used as id).
    var questionText: String { Self.text(for: question) }
}

struct Vitals: Hashable {
    var drinks: String
    var smokes: String
    var diet: String
    var chronotype: String

    /// Nothing answered: what a new account starts with.
    static let blank = Vitals(drinks: "", smokes: "", diet: "", chronotype: "")

    /// Lifestyle answers are saved as their English option ("Early bird", "Never"…), which stays
    /// their identity; this is the text to show. Anything else (free text) is shown as is.
    /// `gender` picks the gendered form where a language has one ("Viandard", "Viandarde").
    static func label(for value: String, gender: DiscoverFilters.Audience? = nil) -> String {
        guard value == "Meat lover" else { return labels[value] ?? value }
        return switch gender {
        case .women: L("Meat lover (woman)")
        case .men: L("Meat lover (man)")
        default: L("Meat lover")
        }
    }

    private static var labels: [String: String] {
        [
            "Very early bird": L("Very early bird"), "Early bird": L("Early bird"), "Night owl": L("Night owl"),
            "Omnivore": L("Omnivore"), "Flexitarian": L("Flexitarian"), "Vegetarian": L("Vegetarian"),
            "Vegan": L("Vegan"), "Pescatarian": L("Pescatarian"),
            "Never": L("Never"), "Rarely": L("Rarely"), "Socially": L("Socially"),
            "Post-race only": L("Post-race only"), "Apéro is sacred": L("Apéro is sacred"),
            "Sometimes": L("Sometimes"), "Yes": L("Yes")
        ]
    }

    /// The drinking answer as a short phrase for summaries ("Drinks socially"); empty if unanswered.
    var drinksSummary: String {
        switch drinks {
        case "": ""
        case "Never": L("No alcohol")
        case "Rarely": L("Drinks rarely")
        case "Socially": L("Drinks socially")
        case "Post-race only": L("Drinks post-race only")
        case "Apéro is sacred": L("Drinks: apéro is sacred")
        default: drinks
        }
    }
}

extension Profile {
    var vitals: Vitals? { vitalsOverride }
    var prompts: [ProfilePrompt] { promptsOverride ?? [] }
}

/// A themed set of prompt questions. Add categories or questions here; the picker scales with them.
struct PromptCategory: Identifiable, Hashable {
    let id: String
    let icon: String
    /// English library text: the stable identity of each question. Show `ProfilePrompt.text(for:)`.
    let questions: [String]

    var name: String {
        switch id {
        case "move": L("On the move")
        case "dating": L("Dating me")
        case "fun": L("Just for fun")
        case "deep": L("A bit deeper")
        default: id
        }
    }
}

extension ProfilePrompt {
    static let library: [PromptCategory] = [
        PromptCategory(id: "move", icon: "running", questions: [
            "My ideal Sunday session",
            "After a workout you'll find me",
            "A stat I'm weirdly proud of",
            "My competitive streak, rated",
            "My pre-race ritual involves",
            "The worst run of my life happened when",
            "I'd drop everything to watch",
            "My playlist for the last kilometre",
            "Rest day? Here's what that really means",
            "The piece of gear I'd save in a fire",
            "I've never been as sore as the day I"
        ]),
        PromptCategory(id: "dating", icon: "heart", questions: [
            "The way to win me over",
            "I'll know it's a match if",
            "Green flag in a training partner",
            "A first date that isn't dinner",
            "I'm looking for someone who",
            "You should not go out with me if",
            "My love language is basically",
            "Together we could finally"
        ]),
        PromptCategory(id: "fun", icon: "smile-circle", questions: [
            "My most irrational fear",
            "My most controversial opinion",
            "I will never shut up about",
            "The snack that fuels my entire personality",
            "Two truths and a lie about my fitness",
            "My hidden talent nobody believes",
            "If I were an energy gel flavour I'd be",
            "The dumbest injury I've ever had",
            "Unpopular opinion about stretching",
            "Karaoke song, no hesitation"
        ]),
        PromptCategory(id: "deep", icon: "stars", questions: [
            "Something I'm training for outside of sport",
            "The best advice a coach ever gave me",
            "What keeps me going on hard days",
            "A goal that scares me a little",
            "I feel most like myself when",
            "The person who got me into sport"
        ])
    ]

    /// Every question in the library, flat.
    static var questions: [String] { library.flatMap(\.questions) }

    /// A library question in the app's language (questions not in the library are shown as is).
    static func text(for question: String) -> String {
        switch question {
        case "My ideal Sunday session": L("My ideal Sunday session")
        case "After a workout you'll find me": L("After a workout you'll find me")
        case "A stat I'm weirdly proud of": L("A stat I'm weirdly proud of")
        case "My competitive streak, rated": L("My competitive streak, rated")
        case "The sport I'm secretly bad at": L("The sport I'm secretly bad at")
        case "My pre-race ritual involves": L("My pre-race ritual involves")
        case "The worst run of my life happened when": L("The worst run of my life happened when")
        case "I'd drop everything to watch": L("I'd drop everything to watch")
        case "My playlist for the last kilometre": L("My playlist for the last kilometre")
        case "Rest day? Here's what that really means": L("Rest day? Here's what that really means")
        case "The piece of gear I'd save in a fire": L("The piece of gear I'd save in a fire")
        case "I've never been as sore as the day I": L("I've never been as sore as the day I")
        case "We'll get along if": L("We'll get along if")
        case "The way to win me over": L("The way to win me over")
        case "I'll know it's a match if": L("I'll know it's a match if")
        case "Green flag in a training partner": L("Green flag in a training partner")
        case "Red flag: you skip": L("Red flag: you skip")
        case "A first date that isn't dinner": L("A first date that isn't dinner")
        case "I'm looking for someone who": L("I'm looking for someone who")
        case "You should not go out with me if": L("You should not go out with me if")
        case "My love language is basically": L("My love language is basically")
        case "Together we could finally": L("Together we could finally")
        case "My most irrational fear": L("My most irrational fear")
        case "My most controversial opinion": L("My most controversial opinion")
        case "I will never shut up about": L("I will never shut up about")
        case "The snack that fuels my entire personality": L("The snack that fuels my entire personality")
        case "Two truths and a lie about my fitness": L("Two truths and a lie about my fitness")
        case "My hidden talent nobody believes": L("My hidden talent nobody believes")
        case "If I were an energy gel flavour I'd be": L("If I were an energy gel flavour I'd be")
        case "The dumbest injury I've ever had": L("The dumbest injury I've ever had")
        case "Unpopular opinion about stretching": L("Unpopular opinion about stretching")
        case "Karaoke song, no hesitation": L("Karaoke song, no hesitation")
        case "Something I'm training for outside of sport": L("Something I'm training for outside of sport")
        case "The best advice a coach ever gave me": L("The best advice a coach ever gave me")
        case "What keeps me going on hard days": L("What keeps me going on hard days")
        case "A goal that scares me a little": L("A goal that scares me a little")
        case "I feel most like myself when": L("I feel most like myself when")
        case "The person who got me into sport": L("The person who got me into sport")
        default: question
        }
    }
}

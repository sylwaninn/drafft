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
    static func label(for value: String) -> String {
        switch value {
        case "Very early bird": L("Very early bird")
        case "Early bird": L("Early bird")
        case "Night owl": L("Night owl")
        case "Omnivore": L("Omnivore")
        case "Flexitarian": L("Flexitarian")
        case "Vegetarian": L("Vegetarian")
        case "Vegan": L("Vegan")
        case "Pescatarian": L("Pescatarian")
        case "Never": L("Never")
        case "Rarely": L("Rarely")
        case "Socially": L("Socially")
        case "Post-race only": L("Post-race only")
        case "Sometimes": L("Sometimes")
        case "Yes": L("Yes")
        default: value
        }
    }
}

extension Profile {
    var vitals: Vitals? { vitalsOverride ?? MockData.extras[id]?.vitals }
    var prompts: [ProfilePrompt] { promptsOverride ?? MockData.extras[id]?.prompts ?? [] }
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
        PromptCategory(id: "move", icon: "figure.run", questions: [
            "My ideal Sunday session",
            "After a workout you'll find me",
            "A stat I'm weirdly proud of",
            "My competitive streak, rated",
            "The sport I'm secretly bad at",
            "My pre-race ritual involves",
            "The worst run of my life happened when",
            "I'd drop everything to watch",
            "My playlist for the last kilometre",
            "Rest day? Here's what that really means",
            "The piece of gear I'd save in a fire",
            "I've never been as sore as the day I"
        ]),
        PromptCategory(id: "dating", icon: "heart.fill", questions: [
            "We'll get along if",
            "The way to win me over",
            "I'll know it's a match if",
            "Green flag in a training partner",
            "Red flag: you skip",
            "A first date that isn't dinner",
            "I'm looking for someone who",
            "You should not go out with me if",
            "My love language is basically",
            "Together we could finally"
        ]),
        PromptCategory(id: "fun", icon: "face.smiling.inverse", questions: [
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
        PromptCategory(id: "deep", icon: "sparkles", questions: [
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

extension MockData {
    struct Extras {
        let vitals: Vitals
        let prompts: [ProfilePrompt]
    }

    static let extras: [String: Extras] = [
        "me": .init(
            vitals: .init(drinks: "Post-race only", smokes: "Never", diet: "Flexitarian", chronotype: "Early bird"),
            prompts: [
                .init(question: "My ideal Sunday session", answer: "25k along the Seine, then a very long breakfast."),
                .init(question: "Green flag in a training partner", answer: "Checks the weather before I do.")
            ]),
        "maya": .init(
            vitals: .init(drinks: "Socially", smokes: "Never", diet: "Vegetarian", chronotype: "Early bird"),
            prompts: [
                .init(question: "My ideal Sunday session", answer: "Muddy trail, zero plans, bakery at the finish."),
                .init(question: "After a workout you'll find me", answer: "Stretching other people's hamstrings. Occupational hazard."),
                .init(question: "We'll get along if", answer: "You think walking the steep bits is a strategy, not a defeat.")
            ]),
        "leo": .init(
            vitals: .init(drinks: "Socially", smokes: "Never", diet: "Omnivore", chronotype: "Early bird"),
            prompts: [
                .init(question: "My most irrational fear", answer: "A flat tyre 60k from home with no CO2 cartridge."),
                .init(question: "Green flag in a training partner", answer: "Points out potholes. Shares gels."),
                .init(question: "I'll know it's a match if", answer: "You beat me at padel and don't gloat. Much.")
            ]),
        "ines": .init(
            vitals: .init(drinks: "Rarely", smokes: "Never", diet: "Pescatarian", chronotype: "Very early bird"),
            prompts: [
                .init(question: "My ideal Sunday session", answer: "2k in an outdoor pool while the city is still asleep."),
                .init(question: "The way to win me over", answer: "Show up at 6:15 with two coffees."),
                .init(question: "After a workout you'll find me", answer: "Smelling of chlorine and sketching buildings.")
            ]),
        "sam": .init(
            vitals: .init(drinks: "Socially", smokes: "Never", diet: "High protein, obviously", chronotype: "Night owl"),
            prompts: [
                .init(question: "Green flag in a training partner", answer: "Re-racks their plates."),
                .init(question: "My most irrational fear", answer: "Someone curling in the squat rack."),
                .init(question: "We'll get along if", answer: "You laugh at puns you pretend to hate.")
            ]),
        "chloe": .init(
            vitals: .init(drinks: "Socially", smokes: "Never", diet: "Omnivore", chronotype: "Early bird"),
            prompts: [
                .init(question: "My ideal Sunday session", answer: "32k long run, negative split, croissant at km 33."),
                .init(question: "A stat I'm weirdly proud of", answer: "Four years without skipping a Tuesday interval."),
                .init(question: "I'll know it's a match if", answer: "You can hold a conversation at marathon pace.")
            ]),
        "noah": .init(
            vitals: .init(drinks: "Socially", smokes: "Never", diet: "Vegetarian", chronotype: "Night owl"),
            prompts: [
                .init(question: "My most irrational fear", answer: "Falling off the easy moves in front of people."),
                .init(question: "The way to win me over", answer: "Cheer for my project like it's the Olympics."),
                .init(question: "After a workout you'll find me", answer: "Drawing the route I just failed.")
            ]),
        "aya": .init(
            vitals: .init(drinks: "Socially", smokes: "Never", diet: "Omnivore", chronotype: "Early bird"),
            prompts: [
                .init(question: "Green flag in a training partner", answer: "Calls the ball, every time."),
                .init(question: "My competitive streak, rated", answer: "11 out of 10. I apologise in advance."),
                .init(question: "We'll get along if", answer: "You're happy to lose a set and win dinner.")
            ]),
        "jonas": .init(
            vitals: .init(drinks: "Rarely", smokes: "Never", diet: "Omnivore", chronotype: "Early bird"),
            prompts: [
                .init(question: "A stat I'm weirdly proud of", answer: "I know where all 14 fountains in Vincennes are."),
                .init(question: "My ideal Sunday session", answer: "Easy 15k, chatting pace, no watch."),
                .init(question: "The way to win me over", answer: "Pace me on my last 400m rep.")
            ]),
        "zoe": .init(
            vitals: .init(drinks: "Socially", smokes: "Never", diet: "Omnivore", chronotype: "Night owl"),
            prompts: [
                .init(question: "Green flag in a training partner", answer: "Warms up without being asked."),
                .init(question: "After a workout you'll find me", answer: "Eating something heavier than what I lifted."),
                .init(question: "My most irrational fear", answer: "Bad posture. Yours. Right now.")
            ]),
        "nina": .init(
            vitals: .init(drinks: "Rarely", smokes: "Never", diet: "Vegetarian", chronotype: "Very early bird"),
            prompts: [
                .init(question: "My ideal Sunday session", answer: "Sunrise 10k, then 30 minutes of yoga on the grass."),
                .init(question: "The way to win me over", answer: "Be at the park gate at 6. Not 6:05."),
                .init(question: "We'll get along if", answer: "You think a sunrise counts as a date.")
            ]),
        "tom": .init(
            vitals: .init(drinks: "Socially", smokes: "Never", diet: "Sandwich-based", chronotype: "Early bird"),
            prompts: [
                .init(question: "My ideal Sunday session", answer: "Gravel loop, one wrong turn, one great view."),
                .init(question: "A stat I'm weirdly proud of", answer: "3 years of bike commuting, zero rainy-day excuses.")
            ]),
        "lucas": .init(
            vitals: .init(drinks: "Socially", smokes: "Never", diet: "Everything, I'm a chef", chronotype: "Night owl"),
            prompts: [
                .init(question: "The way to win me over", answer: "Tell me honestly if the sauce needs salt."),
                .init(question: "After a workout you'll find me", answer: "Cooking for whoever belayed me."),
                .init(question: "We'll get along if", answer: "You'll try the scary move and laugh when you fall.")
            ])
    ]
}

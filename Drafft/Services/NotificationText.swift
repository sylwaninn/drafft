import Foundation

/// Every notification's words, in the app's languages: the same phrases as the server's pushes
/// (drafft-backend `supabase/functions/_shared/texts.ts`), so one event reads the same whichever sends it.
/// WORDING.md, Push: the title is the person's name (or the event, for an anonymous like), never "drafft"
/// (iOS already shows the app's name); the body is one sentence with the useful fact, no emoji of ours, no
/// "!". Casual register: "tu" in French, "du" in German, European Portuguese. French puts a non-breaking
/// space before ":" and inside « ». A body that ends with a session's name has no full stop: that name can
/// be the person's own words, a question included.
enum NotificationText {
    enum Kind {
        case message
        case like
        case superLike
        case match
        /// An emoji on one of your messages, with that message's text (nil: previews off, or not text).
        case reaction(String, String?)
        case sessionProposed(String)
        case sessionAccepted(String)
        case sessionDeclined(String)
        case sessionCancelled(String)
    }

    /// The person's name, or the event for a like: a like stays anonymous, the Likes tab says who it was.
    static func title(_ kind: Kind, name: String, in language: AppLanguage) -> String {
        switch kind {
        case .like: pick(language, en: "New like", fr: "Nouveau like", es: "Nuevo like", de: "Neues Like",
                         it: "Nuovo like", pt: "Novo like", nl: "Nieuwe like")
        case .superLike: pick(language, en: "New super like", fr: "Nouveau super like", es: "Nuevo superlike",
                              de: "Neuer Super Like", it: "Nuovo super like", pt: "Novo super like",
                              nl: "Nieuwe superlike")
        default: who(name, in: language)
        }
    }

    static func body(_ kind: Kind, name _: String, in language: AppLanguage) -> String {
        switch kind {
        case .reaction(let e, let text): reaction(e, to: text, in: language)
        case .message: pick(language,
            en: "New message.", fr: "Nouveau message.", es: "Nuevo mensaje.", de: "Neue Nachricht.",
            it: "Nuovo messaggio.", pt: "Nova mensagem.", nl: "Nieuw bericht.")
        case .like: pick(language,
            en: "Someone liked your profile.", fr: "Quelqu'un a liké ton profil.",
            es: "A alguien le ha gustado tu perfil.", de: "Jemandem gefällt dein Profil.",
            it: "Qualcuno ha messo like al tuo profilo.", pt: "Alguém gostou do teu perfil.",
            nl: "Iemand vindt je profiel leuk.")
        case .superLike: pick(language,
            en: "Someone sent you a super like.", fr: "Quelqu'un t'a envoyé un super like.",
            es: "Alguien te ha enviado un superlike.", de: "Jemand hat dir einen Super Like geschickt.",
            it: "Qualcuno ti ha mandato un super like.", pt: "Alguém enviou-te um super like.",
            nl: "Iemand heeft je een superlike gestuurd.")
        case .match: pick(language,
            en: "It's mutual: propose a first session.",
            fr: "C'est réciproque\u{00A0}: propose une première séance.",
            es: "Es mutuo: proponle una primera sesión.",
            de: "Ihr mögt euch beide: Schlag eine erste Session vor.",
            it: "È reciproco: proponi una prima sessione.", pt: "É recíproco: propõe uma primeira sessão.",
            nl: "Het is wederzijds: stel een eerste sessie voor.")
        case .sessionProposed(let t): pick(language,
            en: "Proposed a session: \(t)", fr: "Te propose une séance\u{00A0}: \(t)",
            es: "Te propone una sesión: \(t)", de: "Schlägt dir eine Session vor: \(t)",
            it: "Ti propone una sessione: \(t)", pt: "Propõe-te uma sessão: \(t)",
            nl: "Stelt een sessie voor: \(t)")
        case .sessionAccepted(let t): pick(language,
            en: "Confirmed the session: \(t)", fr: "A confirmé la séance\u{00A0}: \(t)",
            es: "Ha confirmado la sesión: \(t)", de: "Hat die Session bestätigt: \(t)",
            it: "Ha confermato la sessione: \(t)", pt: "Confirmou a sessão: \(t)",
            nl: "Heeft de sessie bevestigd: \(t)")
        case .sessionDeclined(let t): pick(language,
            en: "Can't make it this time: \(t)", fr: "Ne peut pas cette fois-ci\u{00A0}: \(t)",
            es: "Esta vez no puede: \(t)", de: "Kann diesmal nicht: \(t)", it: "Stavolta non può: \(t)",
            pt: "Desta vez não pode: \(t)", nl: "Kan deze keer niet: \(t)")
        case .sessionCancelled(let t): pick(language,
            en: "Cancelled the session: \(t)", fr: "A annulé la séance\u{00A0}: \(t)",
            es: "Ha cancelado la sesión: \(t)", de: "Hat die Session abgesagt: \(t)",
            it: "Ha annullato la sessione: \(t)", pt: "Cancelou a sessão: \(t)",
            nl: "Heeft de sessie afgezegd: \(t)")
        }
    }

    /// "Reacted ❤️ to “See you at 7?”", or without the message when previews are off. The emoji is the
    /// person's reaction, not ours.
    private static func reaction(_ e: String, to text: String?, in language: AppLanguage) -> String {
        guard let text else {
            return pick(language,
                en: "Reacted \(e) to your message.", fr: "A réagi \(e) à ton message.",
                es: "Ha reaccionado con \(e) a tu mensaje.", de: "Hat mit \(e) auf deine Nachricht reagiert.",
                it: "Ha reagito con \(e) al tuo messaggio.", pt: "Reagiu com \(e) à tua mensagem.",
                nl: "Reageerde met \(e) op je bericht.")
        }
        let t = short(text)
        return pick(language,
            en: "Reacted \(e) to “\(t)”",
            fr: "A réagi \(e) à «\u{00A0}\(t)\u{00A0}»",
            es: "Ha reaccionado con \(e) a «\(t)»",
            de: "Hat mit \(e) auf „\(t)“ reagiert.",
            it: "Ha reagito con \(e) a «\(t)»",
            pt: "Reagiu com \(e) a «\(t)»",
            nl: "Reageerde met \(e) op ‘\(t)’")
    }

    /// The quoted message in a reaction notification: one line's worth.
    private static func short(_ text: String) -> String {
        let t = text.replacingOccurrences(of: "\n", with: " ")
        // design-lint: allow truncation - quoted message in a notification, not UI copy
        return t.count > 60 ? String(t.prefix(59)).trimmingCharacters(in: .whitespaces) + "…" : t
    }

    /// A message with previews on: its text is the body, under the sender's name as the title.
    static func preview(_ text: String, name _: String, in _: AppLanguage) -> String {
        text
    }

    /// The name as the title, or "Someone" when the profile has none (never an empty title).
    private static func who(_ name: String, in language: AppLanguage) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return trimmed }
        return pick(language, en: "Someone", fr: "Quelqu'un", es: "Alguien", de: "Jemand", it: "Qualcuno",
                    pt: "Alguém", nl: "Iemand")
    }

    private static func pick(_ language: AppLanguage, en: String, fr: String, es: String, de: String,
                             it: String, pt: String, nl: String) -> String {
        switch language {
        case .en: en
        case .fr: fr
        case .es: es
        case .de: de
        case .it: it
        case .pt: pt
        case .nl: nl
        }
    }
}

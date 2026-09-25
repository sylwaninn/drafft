import Foundation

/// Every notification sentence, in the app's languages. Notifications are titled "drafft" and
/// these are their bodies, whole sentences with the person's name. Casual register, the way the app
/// talks: "tu" in French, "du" in German, European Portuguese. French puts a non-breaking space
/// before ":" and "!".
enum NotificationText {
    static let title = "drafft"

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

    static func body(_ kind: Kind, name n: String, in language: AppLanguage) -> String {
        switch kind {
        case .reaction(let e, let text): reaction(e, to: text, name: n, in: language)
        case .message: pick(language,
            en: "\(n) sent you a message", fr: "\(n) t'a envoyé un message", es: "\(n) te ha enviado un mensaje",
            de: "\(n) hat dir eine Nachricht geschickt", it: "\(n) ti ha inviato un messaggio",
            pt: "\(n) enviou-te uma mensagem", nl: "\(n) heeft je een bericht gestuurd")
        case .like: pick(language,
            en: "\(n) liked your profile", fr: "\(n) a liké ton profil", es: "A \(n) le gusta tu perfil",
            de: "\(n) gefällt dein Profil", it: "\(n) ha messo like al tuo profilo",
            pt: "\(n) gostou do teu perfil", nl: "\(n) vindt je profiel leuk")
        case .superLike: pick(language,
            en: "\(n) sent you a super like", fr: "\(n) t'a envoyé un super like", es: "\(n) te ha enviado un superlike",
            de: "\(n) hat dir einen Super Like geschickt", it: "\(n) ti ha mandato un super like",
            pt: "\(n) enviou-te um super like", nl: "\(n) heeft je een superlike gestuurd")
        case .match: pick(language,
            en: "It's a match with \(n)! Suggest a first session.",
            fr: "C'est un match avec \(n)\u{00A0}! Propose-lui une première séance.",
            es: "¡Match con \(n)! Proponle una primera sesión.", de: "Match mit \(n)! Schlag eine erste Session vor.",
            it: "Match con \(n)! Proponi una prima sessione.", pt: "Match com \(n)! Propõe uma primeira sessão.",
            nl: "Match met \(n)! Stel een eerste sessie voor.")
        case .sessionProposed(let t): pick(language,
            en: "\(n) suggested a session: \(t)", fr: "\(n) te propose une séance\u{00A0}: \(t)",
            es: "\(n) te propone una sesión: \(t)", de: "\(n) schlägt dir eine Session vor: \(t)",
            it: "\(n) ti propone una sessione: \(t)", pt: "\(n) propõe-te uma sessão: \(t)",
            nl: "\(n) stelt een sessie voor: \(t)")
        case .sessionAccepted(let t): pick(language,
            en: "\(n) is in: \(t)", fr: "\(n) a accepté\u{00A0}: \(t)", es: "\(n) ha aceptado: \(t)",
            de: "\(n) ist dabei: \(t)", it: "\(n) ha accettato: \(t)", pt: "\(n) aceitou: \(t)",
            nl: "\(n) doet mee: \(t)")
        case .sessionDeclined(let t): pick(language,
            en: "\(n) can't make it: \(t)", fr: "\(n) ne peut pas venir\u{00A0}: \(t)", es: "\(n) no puede ir: \(t)",
            de: "\(n) kann nicht: \(t)", it: "\(n) non può venire: \(t)", pt: "\(n) não pode ir: \(t)",
            nl: "\(n) kan niet: \(t)")
        case .sessionCancelled(let t): pick(language,
            en: "\(n) cancelled: \(t)", fr: "\(n) a annulé\u{00A0}: \(t)", es: "\(n) ha cancelado: \(t)",
            de: "\(n) hat abgesagt: \(t)", it: "\(n) ha annullato: \(t)", pt: "\(n) cancelou: \(t)",
            nl: "\(n) heeft afgezegd: \(t)")
        }
    }

    /// "Maya reacted ❤️ to: “See you at 7?”", or without the message when previews are off.
    private static func reaction(_ e: String, to text: String?, name n: String, in language: AppLanguage) -> String {
        guard let text else {
            return pick(language,
                en: "\(n) reacted \(e) to your message", fr: "\(n) a réagi \(e) à ton message",
                es: "\(n) ha reaccionado con \(e) a tu mensaje", de: "\(n) hat mit \(e) auf deine Nachricht reagiert",
                it: "\(n) ha reagito con \(e) al tuo messaggio", pt: "\(n) reagiu com \(e) à tua mensagem",
                nl: "\(n) reageerde met \(e) op je bericht")
        }
        let t = short(text)
        return pick(language,
            en: "\(n) reacted \(e) to: “\(t)”",
            fr: "\(n) a réagi \(e) à\u{00A0}: «\u{00A0}\(t)\u{00A0}»",
            es: "\(n) ha reaccionado con \(e) a: «\(t)»",
            de: "\(n) hat mit \(e) auf „\(t)“ reagiert",
            it: "\(n) ha reagito con \(e) a: «\(t)»",
            pt: "\(n) reagiu com \(e) a: «\(t)»",
            nl: "\(n) reageerde met \(e) op: ‘\(t)’")
    }

    /// The quoted message in a reaction notification: one line's worth.
    private static func short(_ text: String) -> String {
        let t = text.replacingOccurrences(of: "\n", with: " ")
        return t.count > 60 ? String(t.prefix(59)).trimmingCharacters(in: .whitespaces) + "…" : t
    }

    /// A message with previews on: "Maya: Ha, love that." ("Maya : …" in French).
    static func preview(_ text: String, name: String, in language: AppLanguage) -> String {
        language == .fr ? "\(name)\u{00A0}: \(text)" : "\(name): \(text)"
    }

    // MARK: Session reminders

    static func reminderEvening(_ session: String, time: String, in language: AppLanguage) -> String {
        pick(language,
             en: "Tomorrow at \(time): \(session). Pack your kit tonight.",
             fr: "Demain à \(time)\u{00A0}: \(session). Prépare ton sac ce soir.",
             es: "Mañana a las \(time): \(session). Prepara tu bolsa esta noche.",
             de: "Morgen um \(time): \(session). Pack heute Abend deine Sachen.",
             it: "Domani alle \(time): \(session). Prepara la borsa stasera.",
             pt: "Amanhã às \(time): \(session). Prepara o saco esta noite.",
             nl: "Morgen om \(time): \(session). Pak vanavond je tas in.")
    }

    static func reminderHour(_ session: String, in language: AppLanguage) -> String {
        pick(language,
             en: "In an hour: \(session). See you there!",
             fr: "Dans une heure\u{00A0}: \(session). À tout à l'heure\u{00A0}!",
             es: "En una hora: \(session). ¡Nos vemos allí!",
             de: "In einer Stunde: \(session). Bis gleich!",
             it: "Tra un'ora: \(session). A dopo!",
             pt: "Daqui a uma hora: \(session). Até já!",
             nl: "Over een uur: \(session). Tot zo!")
    }

    // MARK: drafft tempo

    static func weeklyBoost(in language: AppLanguage) -> String {
        pick(language,
             en: "Your weekly boost is here. Use it anytime: 30 minutes at the top of decks nearby.",
             fr: "Ton boost de la semaine est là. Utilise-le quand tu veux\u{00A0}: 30 minutes en tête des profils près de toi.",
             es: "Ya tienes tu boost semanal. Úsalo cuando quieras: 30 minutos en lo más alto cerca de ti.",
             de: "Dein Wochen-Boost ist da. Nutz ihn, wann du willst: 30 Minuten ganz oben in deiner Nähe.",
             it: "Il tuo boost settimanale è arrivato. Usalo quando vuoi: 30 minuti in cima ai profili vicino a te.",
             pt: "O teu boost semanal chegou. Usa-o quando quiseres: 30 minutos no topo perto de ti.",
             nl: "Je wekelijkse boost is er. Gebruik hem wanneer je wilt: 30 minuten bovenaan bij mensen in de buurt.")
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

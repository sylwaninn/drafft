import SwiftUI

/// "Get help" from anywhere a check fails or an account is on hold: the topic is filled in, the person
/// adds a few words, and it goes to the team (backend `support`), which replies by email. Signed out (a
/// stuck sign-up or reset), the form also asks where to reply. The reference comes back from the server
/// and is emailed too. Signed out, the message carries a Cloudflare Turnstile token (TurnstileChallenge).
/// Without a topic it's the help center: the person picks one of `HelpTopics.all` first.
struct SupportSheet: View {
    var topic: String?
    /// Already written for the person (a purchase's reference); they can change it.
    var prefill = ""
    /// Sent with the message for the team (a transaction id), never shown.
    var details: [String: String] = [:]
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    /// The topic picked in the help center, none until the person taps one.
    @State private var picked: String?
    @State private var replyEmail = ""
    /// Signed in, the reply goes to the account's email; signed out, to one typed here.
    enum Session { case unknown, signedIn, signedOut }
    @State private var session = Session.unknown
    @State private var sending = false
    @State private var reference: String?
    @State private var error: String?
    /// The server turned the reply address down: said on the field.
    @State private var emailError: String?
    @FocusState private var messageFocused: Bool
    @State private var captcha = TurnstileChallenge()

    /// Newlines count as empty too: the field is multi-line.
    private var hasMessage: Bool { !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var hasEmail: Bool {
        session == .signedIn || replyEmail.trimmingCharacters(in: .whitespaces).wholeMatch(of: /[^\s@]+@[^\s@]+\.[^\s@]+/) != nil
    }
    /// Signed out, sending waits for a Turnstile token.
    private var captchaReady: Bool { session == .signedIn || captcha.token != nil }
    private var replyTo: String { session == .signedIn ? app.email : replyEmail.trimmingCharacters(in: .whitespaces) }
    private var isHelpCenter: Bool { topic == nil }
    static let messageLimit = 4000
    private var sentTopic: String? { topic ?? picked }

    var body: some View {
        AccountSheet(title: isHelpCenter ? L("Help center") : L("Get help"),
                     actionTitle: reference != nil ? L("Done") : L("Send to support"),
                     actionIcon: reference != nil ? "check" : "plain",
                     enabled: reference != nil
                        || (sentTopic != nil && hasMessage && hasEmail && session != .unknown && captchaReady),
                     loading: sending,
                     error: error,
                     finished: reference != nil,
                     hasChanges: reference == nil && hasMessage,
                     screen: .support) {
            if reference != nil { dismiss(); return }
            Task { await send() }
        } content: {
            if let reference {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Image("check")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(DS.Palette.onAccentOnNight)
                        .frame(width: 48, height: 48)
                        .background(DS.Palette.accentOnNight, in: .circle)
                    Text("Message sent.")
                        .font(.display(28))
                        .foregroundStyle(.white)
                    Text("We'll reply at \(replyTo). Your reference is \(reference).")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }
                .padding(DS.Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
                .nightSurface()
                .background(DS.Palette.night, in: .rect(cornerRadius: DS.Radius.xl))
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            } else {
                form
            }
        }
        .task {
            if message.isEmpty { message = prefill }
            session = await Backend.shared.hasSession ? .signedIn : .signedOut
            if session == .signedOut { captcha.start() }
        }
        .background {
            // The widget works out of sight; it only shows (in its own sheet) when Cloudflare asks.
            if session == .signedOut && !captcha.needsInteraction {
                TurnstileView(challenge: captcha)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .sheet(isPresented: $captcha.needsInteraction) {
            Group { TurnstileSheet(challenge: captcha) }.sheetSurface()
        }
        .onChange(of: captcha.failed) { _, failed in
            let message = L("The security check couldn't load. Check your connection and try again.")
            if failed { error = message } else if error == message { error = nil }
        }
        .onDisappear { captcha.stop() }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            if let topic {
                HStack {
                    Text("Topic").font(.subheadline.weight(.semibold)).foregroundStyle(DS.Palette.body)
                    Spacer()
                    Text(topic).font(.subheadline.weight(.semibold)).foregroundStyle(DS.Palette.ink)
                }
                .padding(DS.Space.lg)
                .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
            } else {
                topicPicker
            }

            if session == .signedOut {
                SheetBlock(title: L("Where should we reply?")) {
                    DrafftField(title: L("Email"), text: $replyEmail, prompt: L("you@example.com"),
                                error: emailError, contentType: .emailAddress, keyboard: .emailAddress)
                        .onChange(of: replyEmail) { emailError = nil }
                }
            }

            SheetBlock(title: isHelpCenter ? L("How can we help?") : L("What happened?")) {
                // Grows with the message: room to explain from the start, never a scrolling box.
                TextField(isHelpCenter ? L("Describe your question. If something doesn't work, say what you tapped and what happened.")
                                       : L("A few words help us fix it faster"),
                          text: $message, axis: .vertical)
                    .lineLimit(8...)
                    // The support function's limit: typing stops there.
                    .maxLength(Self.messageLimit, of: $message)
                    .font(.body)
                    .focused($messageFocused)
                    .revealsOnFocus(messageFocused)
                    .padding(DS.Space.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                    .onTapGesture { messageFocused = true }
                    .background(DS.Palette.field, in: .rect(cornerRadius: DS.Radius.md))
                    .overlay {
                        // Same focus ring as DrafftField.
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .strokeBorder(messageFocused ? DS.Palette.ink : DS.Palette.ink.opacity(0.35),
                                          lineWidth: messageFocused ? 2 : 1)
                    }
                    .animation(Motion.gentle, value: messageFocused)
                if session == .signedIn {
                    Text("We read every message and reply to \(app.email).")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.mute)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Help center only: what the message is about, so it reaches the right person. Nothing picked
    /// until the person taps a topic.
    private var topicPicker: some View {
        SheetBlock(title: L("What's it about?")) {
            FlowLayout(spacing: DS.Space.sm) {
                ForEach(HelpTopics.all, id: \.self) { t in
                    let on = picked == t
                    Button {
                        Haptics.select()
                        withAnimation(Motion.snappy) { picked = on ? nil : t }
                    } label: {
                        Text(branded: t, font: .footnote.weight(.semibold))
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, DS.Space.md)
                            .frame(minHeight: 36)
                            .foregroundStyle(on ? DS.Palette.onLime : DS.Palette.ink)
                            .background(on ? AnyShapeStyle(DS.Palette.lime) : AnyShapeStyle(DS.Palette.canvasSoft), in: .capsule)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.94))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private func send() async {
        sending = true
        error = nil
        defer { sending = false }
        let topic = sentTopic ?? ""
        var context: [String: Any] = [
            "app": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "screen": isHelpCenter ? "Help center" : topic
        ]
        if let hold = AccountModeration.shared.hold { context["hold"] = hold.rawValue }
        for (key, value) in details { context[key] = value }
        var body: [String: Any] = [
            "topic": topic,
            "message": message.trimmingCharacters(in: .whitespacesAndNewlines),
            "language": app.language.rawValue,
            "context": context
        ]
        if session != .signedIn {
            body["email"] = replyTo
            if let token = captcha.token { body["turnstileToken"] = token }
        }
        // Single use: whatever the answer, the next send needs a fresh token.
        defer { if session != .signedIn { captcha.renew() } }
        do {
            let data = try await Backend.shared.publicFunction("support", body)
            let answer = try JSONDecoder().decode([String: String].self, from: data)
            // The topic is a sentence in the person's language: only where it was asked from goes.
            Telemetry.track(.supportContacted(topic: isHelpCenter ? "help_center" : "in_context", signedIn: session == .signedIn))
            Haptics.success()
            withAnimation(Motion.bouncy) { reference = answer["reference"] ?? "" }
        } catch {
            Haptics.warning()
            Telemetry.unexpected(error, "support", "send")
            if case Backend.BackendError.http(_, "invalid_email") = error {
                emailError = L("That doesn't look like an email address. Check for typos.")
            } else {
                self.error = Self.failure(error)
            }
        }
    }

    /// Why the message didn't go: the support function's own refusals, else the usual words.
    private static func failure(_ error: Error) -> String {
        switch error {
        case let Backend.BackendError.http(_, detail) where detail.contains("captcha_not_configured"):
            L("Support can't take messages this way right now. Try again later.")
        case let Backend.BackendError.http(_, detail) where detail.contains("captcha_"):
            L("The security check didn't go through. Try again.")
        // Signed out, the limit also runs per day: no promise of an hour.
        case Backend.BackendError.http(429, _): L("You've sent several messages already. Try again later.")
        case Backend.BackendError.http(_, "invalid_message"): L("Your message is too long. Shorten it, then send it again.")
        default: ServerMessage.text(for: error, offline: L("Your message couldn't be sent. Check your connection and try again."))
        }
    }
}

/// Small "Get help" link shown under an error.
struct GetHelpButton: View {
    let topic: String
    @State private var show = false

    var body: some View {
        Button {
            Haptics.tap()
            show = true
        } label: {
            Label("Get help", image: "question-circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.Palette.accentInk)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .sheet(isPresented: $show) { Group { SupportSheet(topic: topic) }.sheetSurface() }
    }
}

/// The help center's topics, in the order people look for them.
enum HelpTopics {
    static var safety: String { L("Safety & reports") }

    static var all: [String] { [
        L("Account & login"), L("Profile & photos"), L("Matches & chats"), L("Sessions"),
        L("drafft tempo & billing"), safety, L("Something doesn't work"), L("Something else")
    ] }
}

/// A support topic, for `.sheet(item:)`.
struct HelpTopic: Identifiable, Hashable { let id: String }

import SwiftUI

/// "Get help" from anywhere a check fails or an account is on hold: the topic is filled in, the person
/// adds a few words, and it goes to the team (backend `support`), which replies by email. Signed out (a
/// stuck sign-up or reset), the form also asks where to reply. The reference comes back from the server
/// and is emailed too. Signed out, the message carries a Cloudflare Turnstile token (TurnstileChallenge).
struct SupportSheet: View {
    let topic: String
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var replyEmail = ""
    /// Signed in, the reply goes to the account's email; signed out, to one typed here.
    enum Session { case unknown, signedIn, signedOut }
    @State private var session = Session.unknown
    @State private var sending = false
    @State private var reference: String?
    @State private var error: String?
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

    var body: some View {
        AccountSheet(title: L("Get help"),
                     actionTitle: reference != nil ? L("Done") : L("Send to support"),
                     actionIcon: reference != nil ? "checkmark" : "paperplane.fill",
                     enabled: reference != nil || (hasMessage && hasEmail && session != .unknown && captchaReady),
                     loading: sending,
                     error: error,
                     hasChanges: reference == nil && hasMessage) {
            if reference != nil { dismiss(); return }
            Task { await send() }
        } content: {
            if let reference {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Image(systemName: "checkmark")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(DS.Palette.onLime)
                        .frame(width: 48, height: 48)
                        .background(DS.Palette.lime, in: .circle)
                    Text("Message sent.")
                        .font(.display(28))
                        .foregroundStyle(.white)
                    Text("We'll reply at \(replyTo). Your reference is \(reference).")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }
                .padding(DS.Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Palette.night, in: .rect(cornerRadius: DS.Radius.xl))
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            } else {
                form
            }
        }
        .task {
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
            HStack {
                Text("Topic").font(.subheadline.weight(.semibold)).foregroundStyle(DS.Palette.body)
                Spacer()
                Text(topic).font(.subheadline.weight(.semibold)).foregroundStyle(DS.Palette.ink)
            }
            .padding(DS.Space.lg)
            .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))

            if session == .signedOut {
                SheetBlock(title: L("Where should we reply?")) {
                    DrafftField(title: L("Email"), text: $replyEmail, prompt: L("you@example.com"),
                                contentType: .emailAddress, keyboard: .emailAddress)
                }
            }

            SheetBlock(title: L("What happened?")) {
                TextField("A few words help us fix it faster", text: $message, axis: .vertical)
                    .lineLimit(4...8)
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
            }

        }
    }

    private func send() async {
        sending = true
        error = nil
        defer { sending = false }
        var context: [String: Any] = [
            "app": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "screen": topic
        ]
        if let hold = AccountModeration.shared.hold { context["hold"] = hold.rawValue }
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
            Haptics.success()
            withAnimation(Motion.bouncy) { reference = answer["reference"] ?? "" }
        } catch let Backend.BackendError.http(_, detail) where detail.contains("captcha_not_configured") {
            Haptics.warning()
            error = L("Support can't take messages this way right now. Try again later.")
        } catch let Backend.BackendError.http(_, detail) where detail.contains("captcha_") {
            Haptics.warning()
            error = L("The security check didn't go through. Try again.")
        } catch Backend.BackendError.http(429, _) {
            Haptics.warning()
            error = L("You've sent several messages already. Try again in an hour.")
        } catch {
            Haptics.warning()
            self.error = L("Your message couldn't be sent. Check your connection and try again.")
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
            Label("Get help", systemImage: "questionmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.Palette.accentInk)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .sheet(isPresented: $show) { Group { SupportSheet(topic: topic) }.sheetSurface() }
    }
}

/// A support topic, for `.sheet(item:)`.
struct HelpTopic: Identifiable, Hashable { let id: String }

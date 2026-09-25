import SwiftUI

/// Shared chrome for the credential screens: sage canvas, 900 headline, form, sticky primary action.
struct AuthScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    let actionTitle: String
    var actionEnabled: Bool
    var loading: Bool
    let action: () -> Void
    /// One line under the action saying why it can't run yet (shown only while it's disabled).
    var reason: String? = nil
    /// Small print under the action (demo hints).
    var footnote: String? = nil
    /// Terrain for the page background (defaults to one derived from the title).
    var backdropSeed: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        FocusScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xxl) {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text(title)
                        .font(.display(40))
                        .displayLeading(40)
                        .foregroundStyle(DS.Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(DS.Palette.body)
                }
                content
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.top, DS.Space.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { PageContourBackdrop(seed: backdropSeed ?? "page-\(title)") }
        .bottomBar {
            VStack(spacing: DS.Space.sm) {
                Button(action: action) {
                    if loading { ProgressView().tint(DS.Palette.onLime) } else { Text(actionTitle) }
                }
                .buttonStyle(.drafftPrimary)
                .disabled(!actionEnabled || loading)
                // Why it's disabled. The line keeps its height when empty, so the button never jumps.
                let why = actionEnabled || loading ? nil : reason
                Text(why ?? " ")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.body)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.opacity)
                    .animation(Motion.snappy, value: why)
                    .accessibilityHidden(why == nil)
                if let footnote {
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(DS.Palette.body)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.top, DS.Space.md)
            .padding(.bottom, DS.Space.sm)
        }
        .toolbarVisibility(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum Validation {
    static func isEmail(_ s: String) -> Bool {
        s.wholeMatch(of: /[A-Z0-9a-z._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/) != nil
    }
}

struct PasswordRule: Identifiable, Sendable {
    let id: String
    let label: String
    let test: @Sendable (String) -> Bool

    static var all: [PasswordRule] { [
        .init(id: "len", label: L("At least 8 characters")) { $0.count >= 8 },
        .init(id: "num", label: L("One number")) { $0.contains(where: \.isNumber) },
        .init(id: "case", label: L("Upper and lower case")) { s in s.contains(where: \.isUppercase) && s.contains(where: \.isLowercase) }
    ] }
}

struct SignUpView: View {
    @Environment(AppModel.self) private var app
    @State private var email = ""
    @State private var password = ""
    @State private var emailTouched = false
    @State private var loading = false
    /// From the server: on the field it's about.
    @State private var problem: AuthProblem?
    @State private var confirming = false
    @FocusState private var focus: Field?

    enum Field { case email, password }

    private var emailError: String? {
        if problem == .emailTaken { return problem?.message }
        guard emailTouched, !email.isEmpty, !Validation.isEmail(email) else { return nil }
        return L("That doesn't look like an email address. Check for typos.")
    }

    private var passwordError: String? {
        guard let problem, problem != .emailTaken else { return nil }
        return problem.message
    }

    private var passedRules: Int { PasswordRule.all.filter { $0.test(password) }.count }
    private var canSubmit: Bool { Validation.isEmail(email) && passedRules == PasswordRule.all.count }

    private var reason: String? {
        if email.isEmpty { return L("Enter your email.") }
        if !Validation.isEmail(email) { return L("Check your email address.") }
        if password.isEmpty { return L("Create a password.") }
        if passedRules < PasswordRule.all.count { return L("Your password doesn't meet every rule yet.") }
        return nil
    }

    var body: some View {
        AuthScaffold(
            title: L("Create your account"),
            subtitle: L("Your email stays private. Matches only see your first name."),
            actionTitle: L("Create account"),
            actionEnabled: canSubmit,
            loading: loading,
            action: submit,
            reason: reason,
            backdropSeed: "page-Create your account"
        ) {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                DrafftField(title: L("Email"), text: $email, prompt: L("you@example.com"), error: emailError,
                            contentType: .username, keyboard: .emailAddress) {
                    emailTouched = true
                    focus = .password
                }
                .focused($focus, equals: .email)
                .onChange(of: focus) { old, _ in if old == .email { emailTouched = true } }

                VStack(alignment: .leading, spacing: DS.Space.md) {
                    DrafftField(title: L("Password"), text: $password, prompt: L("Create a password"), isSecure: true,
                                error: passwordError, contentType: .newPassword, submitLabel: .done, onSubmit: submit)
                        .focused($focus, equals: .password)
                    StrengthBar(passed: passedRules, total: PasswordRule.all.count)
                    VStack(alignment: .leading, spacing: DS.Space.xs + 2) {
                        ForEach(PasswordRule.all) { rule in
                            let ok = rule.test(password)
                            Label {
                                Text(rule.label).foregroundStyle(ok ? DS.Palette.ink : DS.Palette.body)
                            } icon: {
                                // Met: the one selection mark (CheckDisc), not an SF tick.
                                CheckDisc(isOn: ok, size: 22)
                            }
                                .font(.footnote.weight(ok ? .semibold : .regular))
                                .instantWeight()
                                .animation(Motion.snappy, value: ok)
                                .accessibilityElement(children: .combine)
                                .accessibilityValue(ok ? "Met" : "Not met yet")
                        }
                    }
                }
            }
        }
        .navigationDestination(isPresented: $confirming) { ConfirmEmailView(email: email, password: password) }
        .onChange(of: email) { if problem == .emailTaken { problem = nil } }
        .onChange(of: password) { if problem != .emailTaken { problem = nil } }
    }

    private func submit() {
        emailTouched = true
        guard canSubmit else { return }
        loading = true
        problem = nil
        Task {
            defer { loading = false }
            do {
                switch try await Backend.shared.signUp(email: email, password: password) {
                case .signedIn:
                    Haptics.success()
                    app.email = email
                    app.signIn(onboard: true)
                case .confirmEmail:
                    Haptics.success()
                    confirming = true
                }
            } catch {
                Haptics.warning()
                problem = AuthProblem(error)
            }
        }
    }
}

/// After sign-up, when the account needs its email confirmed: the link in the email opens the app
/// and carries on to sign-up by itself; "I've confirmed" covers opening it on another device.
struct ConfirmEmailView: View {
    let email: String
    let password: String
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var loading = false
    @State private var problem: AuthProblem?
    @State private var resent = false

    var body: some View {
        AuthScaffold(
            title: L("Check your inbox"),
            subtitle: L("We sent a link to \(email). Open it on this iPhone to confirm your email and carry on."),
            actionTitle: L("I've confirmed my email"),
            actionEnabled: true,
            loading: loading,
            action: logIn,
            backdropSeed: "page-Create your account"
        ) {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                if let problem {
                    Label(problem.message, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(DS.Palette.negative)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    if let url = URL(string: "message://") { openURL(url) }
                } label: { Label("Open Mail", systemImage: "envelope.open.fill") }
                    .buttonStyle(.drafftSecondary)
                Button(resent ? L("Email sent again") : L("Resend the email")) { resend() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(resent ? DS.Palette.body : DS.Palette.accentInk)
                    .buttonStyle(.textLink)
                    .disabled(resent)
            }
        }
    }

    private func logIn() {
        loading = true
        problem = nil
        Task {
            defer { loading = false }
            do {
                try await Backend.shared.signIn(email: email, password: password)
                Haptics.success()
                app.email = email
                app.signIn(onboard: true)
            } catch {
                Haptics.warning()
                problem = AuthProblem(error)
            }
        }
    }

    private func resend() {
        Task {
            do {
                try await Backend.shared.resendConfirmation(to: email)
                resent = true
            } catch {
                problem = AuthProblem(error)
            }
        }
    }
}

struct StrengthBar: View {
    let passed: Int
    let total: Int
    var body: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i < passed ? color : DS.Palette.ink.opacity(0.1))
                    .frame(height: 6)
            }
        }
        .animation(Motion.snappy, value: passed)
        .accessibilityElement()
        .accessibilityLabel("Password strength \(passed) of \(total)")
    }

    private var color: Color {
        switch passed {
        case total: DS.Palette.lime
        case 2: DS.Palette.warning
        default: DS.Palette.negative
        }
    }
}

struct LogInView: View {
    @Environment(AppModel.self) private var app
    @State private var email = ""
    @State private var password = ""
    /// Errors sit on the field they're about.
    @State private var emailError: String?
    @State private var passwordError: String?
    @State private var loading = false
    @State private var showReset = false
    @FocusState private var focus: SignUpView.Field?

    var body: some View {
        AuthScaffold(
            title: L("Welcome back"),
            subtitle: L("Log in to see who's new nearby."),
            actionTitle: L("Log in"),
            actionEnabled: !email.isEmpty && !password.isEmpty,
            loading: loading,
            action: submit,
            reason: email.isEmpty ? L("Enter your email.") : password.isEmpty ? L("Enter your password.") : nil,
            backdropSeed: BackdropSeed.login
        ) {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                DrafftField(title: L("Email"), text: $email, prompt: L("you@example.com"), error: emailError,
                            contentType: .username, keyboard: .emailAddress) { focus = .password }
                    .focused($focus, equals: .email)
                DrafftField(title: L("Password"), text: $password, prompt: L("Your password"), isSecure: true,
                            error: passwordError, contentType: .password, submitLabel: .go, onSubmit: submit)
                    .focused($focus, equals: .password)
                    // On the password label's line, where people look for it.
                    .overlay(alignment: .topTrailing) {
                        Button("Forgot?") { showReset = true }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DS.Palette.accentInk)
                            .buttonStyle(.textLink)
                            .offset(y: -12)
                            .accessibilityLabel("Forgot password")
                    }
            }
        }
        .onChange(of: email) { emailError = nil }
        .onChange(of: password) { passwordError = nil }
        // Its own page, pushed like the rest of the auth flow (not an alert).
        .navigationDestination(isPresented: $showReset) { ResetPasswordView(email: email) }
    }

    private func submit() {
        // Keyboard "Go" with a field still empty: move to it, no error.
        if email.isEmpty { focus = .email; return }
        if password.isEmpty { focus = .password; return }
        guard Validation.isEmail(email) else {
            emailError = L("That doesn't look like an email address. Check for typos.")
            focus = .email
            Haptics.warning()
            return
        }
        loading = true
        Task {
            defer { loading = false }
            do {
                try await Backend.shared.signIn(email: email, password: password)
                Haptics.success()
                app.email = email
                // Someone who stopped mid sign-up goes back to it.
                let onboarded = (try? await Backend.shared.isOnboarded()) ?? true
                app.signIn(onboard: !onboarded)
            } catch {
                Haptics.warning()
                let problem = AuthProblem(error)
                if problem == .emailNotConfirmed { emailError = problem.message } else { passwordError = problem.message }
            }
        }
    }
}

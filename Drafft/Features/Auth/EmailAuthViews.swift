import SwiftUI

/// Shared chrome for the credential screens: sage canvas, 900 headline, form, sticky primary action.
struct AuthScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    let actionTitle: String
    var actionEnabled: Bool
    var loading: Bool
    let action: () -> Void
    /// Small print under the action (demo hints).
    var footnote: String? = nil
    /// A problem that isn't about one field (no connection, a server error), in red under the action.
    var error: String?
    /// Terrain for the page background (defaults to one derived from the title).
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
        .background { Rectangle().fill(DS.Palette.canvasSoft).ignoresSafeArea() }
        // The title scrolls under the system back button: the same edge blur as every bar.
        .blurredNavigationEdge()
        .bottomBar {
            VStack(spacing: DS.Space.sm) {
                Button(action: action) {
                    if loading { ProgressView().tint(DS.Palette.onLime) } else { Text(actionTitle) }
                }
                .buttonStyle(.drafftPrimary)
                .disabled(!actionEnabled || loading)
                if let error {
                    Text(error)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(DS.Palette.negative)
                        .multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                }
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
        if problem == .emailTaken || problem == .invalidEmail { return problem?.message }
        guard emailTouched, !email.isEmpty, !Validation.isEmail(email) else { return nil }
        return L("That doesn't look like an email address. Check for typos.")
    }

    private var passwordError: String? { problem == .weakPassword ? problem?.message : nil }

    /// Not about one field (no connection, too many emails, a server error): under the action.
    private var formError: String? {
        guard let problem, problem != .emailTaken, problem != .invalidEmail, problem != .weakPassword else { return nil }
        return problem.message
    }

    private var passedRules: Int { PasswordRule.all.filter { $0.test(password) }.count }
    private var canSubmit: Bool { Validation.isEmail(email) && passedRules == PasswordRule.all.count }

    var body: some View {
        AuthScaffold(
            title: L("Create your account"),
            subtitle: L("Your email stays private. Matches only see your first name."),
            actionTitle: L("Create account"),
            actionEnabled: canSubmit,
            loading: loading,
            action: submit,
            error: formError
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
                    VStack(alignment: .leading, spacing: DS.Space.xs + 2) {
                        ForEach(PasswordRule.all) { rule in
                            let ok = rule.test(password)
                            Label {
                                Text(rule.label).foregroundStyle(ok ? DS.Palette.ink : DS.Palette.body)
                            } icon: {
                                // Met: the one selection mark (CheckDisc), not an SF tick.
                                CheckDisc(isOn: ok, size: 22)
                            }
                                .font(.footnote.weight(.medium))
                                .animation(Motion.snappy, value: ok)
                                .accessibilityElement(children: .combine)
                                .accessibilityValue(ok ? "Met" : "Not met yet")
                        }
                    }
                }
            }
        }
        .navigationDestination(isPresented: $confirming) { ConfirmEmailView(email: email) }
        .onChange(of: email) { if problem != .weakPassword { problem = nil } }
        .onChange(of: password) { if problem != .emailTaken && problem != .invalidEmail { problem = nil } }
    }

    private func submit() {
        emailTouched = true
        guard canSubmit else { return }
        loading = true
        problem = nil
        Task {
            defer { loading = false }
            do {
                switch try await Backend.shared.signUp(
                    email: email, password: password, language: Localization.shared.language
                ) {
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

/// After sign-up, when the account needs its email confirmed: the 6-digit code from the email.
/// The sixth digit checks it and signs in; Change goes back to the form.
struct ConfirmEmailView: View {
    let email: String
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var flow = EmailCodeModel()

    var body: some View {
        AuthScaffold(
            title: L("Check your inbox"),
            subtitle: L("Enter the 6-digit code we sent you."),
            actionTitle: L("Continue"),
            actionEnabled: flow.stage == .code && flow.code.count == 6,
            loading: flow.busy,
            action: verify
        ) {
            if flow.stage == .locked {
                CodeLockedCard(message: flow.error)
            } else {
                OneTimeCodeEntry(destination: email, code: flow.code, onCode: flow.enterCode,
                                 busy: flow.busy, error: flow.error, needsHelp: flow.needsHelp,
                                 helpTopic: L("Create your account"),
                                 hint: L("Check your inbox, and your spam folder. The code works for 1 hour."),
                                 resendIn: flow.resendIn,
                                 onEdit: { dismiss() },
                                 onResend: { Task { await flow.resend() } })
            }
        }
        .onAppear {
            guard flow.stage == .form else { return }
            let email = email
            flow.awaitCode(sentTo: email) {
                try await Backend.shared.resendConfirmation(to: email)
            } verify: { code in
                try await Backend.shared.confirmSignUp(email, code: code)
            }
        }
        .onChange(of: flow.stage) { _, stage in
            guard stage == .done else { return }
            app.email = email
            app.signIn(onboard: true)
        }
    }

    private func verify() { Task { await flow.verify() } }
}

struct LogInView: View {
    @Environment(AppModel.self) private var app
    @State private var email = ""
    @State private var password = ""
    /// Errors sit on the field they're about.
    @State private var emailError: String?
    @State private var passwordError: String?
    /// Not about one field (no connection, too many tries, a server error): under the action.
    @State private var formError: String?
    @State private var loading = false
    @State private var showReset = false
    /// An account whose email was never confirmed: its code comes first (sign-up goes email, code, phone).
    @State private var confirmingEmail = false
    @FocusState private var focus: SignUpView.Field?

    var body: some View {
        AuthScaffold(
            title: L("Welcome back"),
            subtitle: L("Log in to see who's new nearby."),
            actionTitle: L("Log in"),
            actionEnabled: !email.isEmpty && !password.isEmpty,
            loading: loading,
            action: submit,
            error: formError
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
        .onChange(of: email) { emailError = nil; formError = nil }
        .onChange(of: password) { passwordError = nil; formError = nil }
        // Its own page, pushed like the rest of the auth flow (not an alert).
        .navigationDestination(isPresented: $showReset) { ResetPasswordView(email: email) }
        .navigationDestination(isPresented: $confirmingEmail) { ConfirmEmailView(email: email) }
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
        formError = nil
        Task {
            defer { loading = false }
            do {
                try await Backend.shared.signIn(email: email, password: password)
                Haptics.success()
                app.email = email
                // Someone who stopped mid sign-up goes back to it.
                // (The account read here is the one sign-in then uses: read once.)
                await app.enterAfterLogIn()
            } catch {
                Haptics.warning()
                let problem = AuthProblem(error)
                if problem == .emailNotConfirmed {
                    await confirmEmailFirst()
                } else if problem == .wrongCredentials {
                    passwordError = problem.message
                } else {
                    formError = problem.message
                }
            }
        }
    }

    /// An account whose email was never confirmed: a new code, then the code step (confirming it signs
    /// in and goes on to sign-up). Too many emails means a recent code is still on its way: the code step
    /// too, where Resend waits. Anything else is said, not a code screen without a code.
    private func confirmEmailFirst() async {
        do {
            try await Backend.shared.resendConfirmation(to: email)
            confirmingEmail = true
        } catch {
            let problem = AuthProblem(error)
            if problem == .tooManyEmails { confirmingEmail = true } else { formError = problem.message }
        }
    }
}

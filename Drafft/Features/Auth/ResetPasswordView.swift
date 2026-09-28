import SwiftUI

/// Forgot password, all in the app: the email, then the 6-digit code sent to it, then the new password,
/// and the person is logged in. No link. The code step never says whether the address has an account
/// (no account enumeration): Auth sends nothing to an unknown address, and the code is simply wrong.
struct ResetPasswordView: View {
    @State var email: String
    @Environment(AppModel.self) private var app
    @State private var flow = EmailCodeModel()
    @State private var password = ""
    @State private var saving = false
    @State private var saved = false
    @State private var problem: AuthProblem?
    @State private var showHelp = false
    @FocusState private var focused: Bool

    private var passedRules: Int { PasswordRule.all.filter { $0.test(password) }.count }

    private var title: String {
        switch flow.stage {
        case .form: L("Reset your password")
        case .code, .locked: L("Check your inbox")
        case .done: L("Choose a new password")
        }
    }

    private var subtitle: String {
        switch flow.stage {
        case .form: L("Enter the email you signed up with. We'll send you a 6-digit code.")
        case .code, .locked: L("Enter the 6-digit code we sent you.")
        case .done: L("You'll use it to log in from now on.")
        }
    }

    private var actionTitle: String {
        switch flow.stage {
        case .form: L("Send code")
        case .code: L("Continue")
        case .done: L("Save password")
        case .locked: L("Get help")
        }
    }

    private var actionEnabled: Bool {
        switch flow.stage {
        case .form: Validation.isEmail(email)
        case .code: flow.code.count == 6
        case .done: passedRules == PasswordRule.all.count
        case .locked: true
        }
    }

    var body: some View {
        AuthScaffold(title: title, subtitle: subtitle, actionTitle: actionTitle, actionEnabled: actionEnabled,
                     loading: flow.busy || saving, action: primary, backdropSeed: BackdropSeed.login) {
            Group {
                switch flow.stage {
                case .form: emailForm
                case .code:
                    OneTimeCodeEntry(destination: flow.sentTo, code: flow.code, onCode: flow.enterCode,
                                     busy: flow.busy, error: flow.error, needsHelp: flow.needsHelp,
                                     helpTopic: L("Password reset"),
                                     hint: L("Check your inbox, and your spam folder. The code works for 1 hour."),
                                     resendIn: flow.resendIn,
                                     onEdit: { flow.edit() },
                                     onResend: { Task { await flow.resend() } })
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                case .done: passwordForm.transition(.opacity.combined(with: .move(edge: .trailing)))
                case .locked: CodeLockedCard(message: flow.error)
                }
            }
            .animation(Motion.snappy, value: flow.stage)
        }
        .onChange(of: email) { if flow.stage == .form { flow.error = nil } }
        .onChange(of: password) { problem = nil }
        // The code signed in only to set the password: leaving before it's saved leaves no session behind.
        .onDisappear {
            guard flow.stage == .done, !saved else { return }
            Task { await Backend.shared.signOut() }
        }
        .sheet(isPresented: $showHelp) { Group { SupportSheet(topic: L("Password reset")) }.sheetSurface() }
    }

    private var emailForm: some View {
        DrafftField(title: L("Email"), text: $email, prompt: L("you@example.com"), error: flow.error,
                    contentType: .username, keyboard: .emailAddress, submitLabel: .send, onSubmit: primary)
            .focused($focused)
    }

    private var passwordForm: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            DrafftField(title: L("New password"), text: $password, prompt: L("Create a password"), isSecure: true,
                        error: problem?.message, contentType: .newPassword, submitLabel: .done, onSubmit: primary)
            StrengthBar(passed: passedRules, total: PasswordRule.all.count)
            VStack(alignment: .leading, spacing: DS.Space.xs + 2) {
                ForEach(PasswordRule.all) { rule in
                    let ok = rule.test(password)
                    Label {
                        Text(rule.label).foregroundStyle(ok ? DS.Palette.ink : DS.Palette.body)
                    } icon: {
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

    private func primary() {
        guard actionEnabled else { return }
        switch flow.stage {
        case .form:
            focused = false
            let email = email.trimmingCharacters(in: .whitespaces)
            Task {
                await flow.send(to: email) {
                    try await Backend.shared.sendPasswordReset(to: email)
                } verify: { code in
                    try await Backend.shared.verifyPasswordReset(email, code: code)
                }
            }
        case .code: Task { await flow.verify() }
        case .done: save()
        case .locked: showHelp = true
        }
    }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            do {
                try await Backend.shared.updatePassword(password)
                saved = true
                Haptics.success()
                app.email = flow.sentTo
                // Someone who stopped mid sign-up goes back to it.
                let onboarded = (try? await Backend.shared.isOnboarded()) ?? true
                app.signIn(onboard: !onboarded)
            } catch {
                Haptics.warning()
                problem = AuthProblem(error)
            }
        }
    }
}

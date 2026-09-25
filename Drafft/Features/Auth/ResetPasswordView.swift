import SwiftUI

/// Forgot password: one field, one action, then a clear "check your inbox" state with a way to
/// open Mail, resend (after a short wait) or go back to log in. The message never says whether
/// the address has an account (no account enumeration).
struct ResetPasswordView: View {
    @State var email: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @FocusState private var focused: Bool

    enum Stage: Equatable { case enter, sending, sent, failed }
    @State private var stage: Stage = .enter
    @State private var resendIn = 0
    /// Resending stays on the "check your inbox" page (no flash back to the form).
    @State private var resending = false
    @State private var emailError: String?

    private var valid: Bool { Validation.isEmail(email) }

    var body: some View {
        FocusScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xxl) {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text(stage == .sent ? "Check your inbox" : "Reset your password")
                        .font(.display(40))
                        .displayLeading(40)
                        .foregroundStyle(DS.Palette.ink)
                        .contentTransition(.opacity)
                        .accessibilityAddTraits(.isHeader)
                    Text(branded: stage == .sent
                         ? L("If \(email) has a drafft account, a reset link is on its way. It works for 30 minutes. Nothing after a few minutes? Check your spam folder.")
                         : L("Enter the email you signed up with. We'll send you a link to choose a new password."),
                         font: .body)
                        .foregroundStyle(DS.Palette.body)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if stage != .sent {
                    VStack(alignment: .leading, spacing: DS.Space.md) {
                        DrafftField(title: L("Email"), text: $email, prompt: L("you@example.com"), error: emailError,
                                    contentType: .username, keyboard: .emailAddress, submitLabel: .send, onSubmit: send)
                            .focused($focused)
                        if stage == .failed {
                            VStack(alignment: .leading, spacing: 0) {
                                Label("We couldn't send the link. Check your connection and try again.",
                                      systemImage: "exclamationmark.circle.fill")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(DS.Palette.negative)
                                GetHelpButton(topic: L("Password reset"))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.top, DS.Space.lg)
            .animation(Motion.snappy, value: stage)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { PageContourBackdrop(seed: BackdropSeed.login) }
        .bottomBar {
            VStack(spacing: DS.Space.sm) {
                if stage == .sent {
                    // One action that moves things forward; the rest are quiet links.
                    Button {
                        if let url = URL(string: "message://") { openURL(url) }
                    } label: { Label("Open Mail", systemImage: "envelope.open.fill") }
                        .buttonStyle(.drafftPrimary)
                    Button {
                        Task { await sendLink(resend: true) }
                    } label: {
                        if resending {
                            ProgressView().tint(DS.Palette.ink).frame(minHeight: 44)
                        } else {
                            Text(resendIn > 0 ? "Resend in 0:\(String(format: "%02d", resendIn))" : "Resend the link")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(resendIn > 0 ? DS.Palette.body : DS.Palette.accentInk)
                                .rollingDigits(wording: resendIn > 0, countsDown: true)
                                .frame(minHeight: 44)
                                .contentShape(.rect)
                        }
                    }
                    .disabled(resendIn > 0 || resending)
                } else {
                    Button(action: send) {
                        if stage == .sending { ProgressView().tint(DS.Palette.onLime) }
                        else { Label("Send reset link", systemImage: "paperplane.fill") }
                    }
                    .buttonStyle(.drafftPrimary)
                    .disabled(email.isEmpty || stage == .sending)
                    // Why it's disabled; keeps its height when empty.
                    Text(email.isEmpty ? "Enter your email." : " ")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.body)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(!email.isEmpty)
                }
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.top, DS.Space.md)
            .padding(.bottom, DS.Space.sm)
        }
        .toolbarVisibility(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: email) { emailError = nil; if stage == .failed { stage = .enter } }
    }

    private func send() {
        guard !email.isEmpty else { focused = true; return }
        guard valid else {
            emailError = L("That doesn't look like an email address.")
            Haptics.warning()
            return
        }
        focused = false
        Task { await sendLink() }
    }

    private func sendLink(resend: Bool = false) async {
        if resend { resending = true } else { stage = .sending }
        // The same answer whether or not the address has an account (no account enumeration).
        let sent = (try? await Backend.shared.sendPasswordReset(to: email)) != nil
        resending = false
        if !sent {
            Haptics.warning()
            stage = .failed
            return
        }
        Haptics.success()
        stage = .sent
        resendIn = 30
        while resendIn > 0 {
            try? await Task.sleep(for: .seconds(1))
            resendIn -= 1
        }
    }
}

/// Opened by the link in the reset email (the app is signed in by then): the new password, with
/// the same rules as sign-up.
struct NewPasswordView: View {
    @Environment(AppModel.self) private var app
    @State private var password = ""
    @State private var loading = false
    @State private var problem: AuthProblem?

    private var passedRules: Int { PasswordRule.all.filter { $0.test(password) }.count }

    var body: some View {
        AuthScaffold(
            title: L("Choose a new password"),
            subtitle: L("You'll use it to log in from now on."),
            actionTitle: L("Save password"),
            actionEnabled: passedRules == PasswordRule.all.count,
            loading: loading,
            action: save,
            backdropSeed: BackdropSeed.login
        ) {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                DrafftField(title: L("New password"), text: $password, prompt: L("Create a password"), isSecure: true,
                            error: problem?.message, contentType: .newPassword, submitLabel: .done, onSubmit: save)
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
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(ok ? "Met" : "Not met yet")
                    }
                }
            }
        }
        .onChange(of: password) { problem = nil }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close", systemImage: "xmark") { app.choosingNewPassword = false }
            }
        }
    }

    private func save() {
        guard passedRules == PasswordRule.all.count else { return }
        loading = true
        Task {
            defer { loading = false }
            do {
                try await Backend.shared.updatePassword(password)
                Haptics.success()
                app.choosingNewPassword = false
                await app.restoreSession()
            } catch {
                Haptics.warning()
                problem = AuthProblem(error)
            }
        }
    }
}

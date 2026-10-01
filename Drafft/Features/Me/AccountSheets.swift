import SwiftUI
import StoreKit

/// Shared chrome for account sheets: title, close on the right, content blocks,
/// and a pinned primary action that stays visible (disabled until it can run; only a real error under it).
struct AccountSheet<Content: View>: View {
    let title: String
    let actionTitle: String
    var actionIcon: String?
    var destructive = false
    var enabled: Bool
    var loading = false
    /// A real problem (turned down, failed), in red under the action. Never why it's disabled.
    var error: String?
    /// Something typed that closing would lose: Close asks before discarding it.
    var hasChanges = false
    let action: () -> Void
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss
    @State private var confirmDiscard = false

    var body: some View {
        NavigationStack {
            FocusScrollView {
                VStack(spacing: DS.Space.md) { content }
                    .padding(.horizontal, DS.Space.lg)
                    .padding(.vertical, DS.Space.sm)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DS.Palette.canvasSoft)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", image: .icon("close")) {
                        if hasChanges { confirmDiscard = true } else { dismiss() }
                    }
                }
            }
            .drafftConfirm(isPresented: $confirmDiscard, icon: "trash-bin-minimalistic",
                           title: L("Discard your changes?"),
                           message: L("What you typed here will be lost."),
                           cancelTitle: L("Keep editing"),
                           actions: [ConfirmAction(title: L("Discard changes"), kind: .destructive) { dismiss() }])
            .blurredNavigationEdge()
            .bottomBar {
                VStack(spacing: DS.Space.sm) {
                    Button(action: action) {
                        if loading {
                            ProgressView().tint(destructive ? .white : DS.Palette.onLime)
                        } else if let actionIcon {
                            Label(actionTitle, image: actionIcon)
                        } else {
                            Text(actionTitle)
                        }
                    }
                    .buttonStyle(DestructiveAwareStyle(destructive: destructive))
                    .disabled(!enabled || loading)
                    .draftTrail(RoundedRectangle(cornerRadius: DS.Radius.xl),
                                color: destructive ? DS.Palette.negative : DS.Palette.lime,
                                step: CGSize(width: -6, height: 0))
                    .padding(.leading, 12)
                    if let error {
                        Text(error)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(DS.Palette.negative)
                            .multilineTextAlignment(.center)
                            .contentTransition(.opacity)
                    }
                }
                .padding(.horizontal, DS.Space.xl)
                .padding(.top, DS.Space.md)
                .padding(.bottom, DS.Space.sm)
            }
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(hasChanges)
    }
}

private struct DestructiveAwareStyle: ButtonStyle {
    let destructive: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        if destructive {
            configuration.label
                .font(.body.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.9)
                .padding(.vertical, DS.Space.xs)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.horizontal, DS.Space.xl)
                .foregroundStyle(.white)
                .background(DS.Palette.negative, in: .rect(cornerRadius: DS.Radius.xl))
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(Motion.snappy, value: configuration.isPressed)
        } else {
            DrafftButtonStyle(kind: .primary).makeBody(configuration: configuration)
        }
    }
}

/// A group in a sheet, with an optional small title: a sage well on the white sheet (a white block
/// on a page), like every sheet in You. Its fields stay white, so they stand out of the well.
struct SheetBlock<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            if let title {
                Text(title).font(.headline).foregroundStyle(DS.Palette.ink).accessibilityAddTraits(.isHeader)
            }
            content
        }
        .padding(DS.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
    }
}

// MARK: - Email

/// New address and password, then the 6-digit code sent to the new address (as at sign-up).
struct ChangeEmailSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var newEmail = ""
    @State private var password = ""
    @State private var flow = EmailCodeModel()
    @State private var showHelp = false

    private var valid: Bool {
        Validation.isEmail(newEmail) && newEmail.lowercased() != app.email.lowercased() && !password.isEmpty
    }

    private var actionTitle: String {
        switch flow.stage {
        case .form: L("Send code")
        case .code: L("Verify")
        case .done: L("Done")
        case .locked: L("Get help")
        }
    }

    private var enabled: Bool {
        switch flow.stage {
        case .form: valid
        case .code: flow.code.count == 6
        case .done, .locked: true
        }
    }

    /// What's wrong with what was typed (nothing about what's missing: the form says it).
    private var error: String? {
        guard flow.stage == .form else { return nil }
        if let error = flow.error { return error }
        if !newEmail.isEmpty && !Validation.isEmail(newEmail) { return L("That doesn't look like an email address.") }
        if !newEmail.isEmpty && newEmail.lowercased() == app.email.lowercased() { return L("That's already your email.") }
        return nil
    }

    var body: some View {
        AccountSheet(title: L("Email"), actionTitle: actionTitle,
                     actionIcon: flow.stage == .form ? "plain" : flow.stage == .done ? "check" : nil,
                     enabled: enabled, loading: flow.busy, error: error,
                     hasChanges: flow.stage == .code || (flow.stage == .form && !(newEmail.isEmpty && password.isEmpty))) {
            switch flow.stage {
            case .form: send()
            case .code: Task { await flow.verify() }
            case .done: dismiss()
            case .locked: showHelp = true
            }
        } content: {
            Group {
                switch flow.stage {
                case .form: form
                case .code:
                    SheetBlock {
                        OneTimeCodeEntry(destination: flow.sentTo, code: flow.code, onCode: flow.enterCode,
                                         busy: flow.busy, error: flow.error, needsHelp: flow.needsHelp,
                                         helpTopic: L("Email change"),
                                         hint: L("Check your inbox, and your spam folder. The code works for 1 hour."),
                                         resendIn: flow.resendIn,
                                         onEdit: { flow.edit() },
                                         onResend: { Task { await flow.resend() } })
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                case .done: CodeVerifiedCard(title: L("Email updated"), detail: flow.sentTo)
                case .locked: CodeLockedCard(message: flow.error)
                }
            }
            .animation(Motion.snappy, value: flow.stage)
        }
        .onChange(of: flow.stage) { _, s in if s == .done { app.email = flow.sentTo } }
        .onChange(of: newEmail) { if flow.stage == .form { flow.error = nil } }
        .onChange(of: password) { if flow.stage == .form { flow.error = nil } }
        .sheet(isPresented: $showHelp) { Group { SupportSheet(topic: L("Email change")) }.sheetSurface() }
    }

    @ViewBuilder
    private var form: some View {
        SheetBlock(title: L("Current email")) {
            Text(app.email).font(.body.weight(.semibold)).foregroundStyle(DS.Palette.body)
        }
        SheetBlock(title: L("New email")) {
            DrafftField(title: L("Email"), text: $newEmail, prompt: L("you@example.com"),
                        contentType: .emailAddress, keyboard: .emailAddress)
            DrafftField(title: L("Your password"), text: $password, prompt: L("To confirm it's you"),
                        isSecure: true, contentType: .password, submitLabel: .send,
                        onSubmit: { if valid { send() } })
        }
    }

    private func send() {
        let email = newEmail.trimmingCharacters(in: .whitespaces)
        let current = app.email
        let password = password
        flow.messages = [.wrongCredentials: L("Your password is incorrect."),
                         .emailTaken: L("This email is already linked to another drafft account. Use another one.")]
        flow.formProblems = [.emailTaken, .invalidEmail]
        Task {
            await flow.send(to: email) {
                // The password proves it's them; the code proves the new address is theirs.
                try await Backend.shared.signIn(email: current, password: password)
                try await Backend.shared.updateEmail(email)
            } verify: { code in
                try await Backend.shared.confirmEmailChange(email, code: code)
            }
        }
    }
}

// MARK: - Password

/// New password, then a 6-digit code sent to the account's email: the code proves it's them.
struct ChangePasswordSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var new = ""
    @State private var confirm = ""
    @State private var flow = EmailCodeModel()
    @State private var showHelp = false

    private var passed: Int { PasswordRule.all.filter { $0.test(new) }.count }
    private var valid: Bool { passed == PasswordRule.all.count && new == confirm }

    private var actionTitle: String {
        switch flow.stage {
        case .form: L("Send code")
        case .code: L("Update password")
        case .done: L("Done")
        case .locked: L("Get help")
        }
    }

    private var enabled: Bool {
        switch flow.stage {
        case .form: valid
        case .code: flow.code.count == 6
        case .done, .locked: true
        }
    }

    /// What's wrong with what was typed (nothing about what's missing: the form says it).
    private var error: String? {
        guard flow.stage == .form else { return nil }
        if let error = flow.error { return error }
        if !confirm.isEmpty && new != confirm { return L("The two new passwords don't match.") }
        return nil
    }

    var body: some View {
        AccountSheet(title: L("Password"), actionTitle: actionTitle,
                     actionIcon: flow.stage == .form ? "plain" : flow.stage == .code ? "lock-keyhole-minimalistic"
                         : flow.stage == .done ? "check" : nil,
                     enabled: enabled, loading: flow.busy, error: error,
                     hasChanges: flow.stage == .code || (flow.stage == .form && !(new.isEmpty && confirm.isEmpty))) {
            switch flow.stage {
            case .form: send()
            case .code: Task { await flow.verify() }
            case .done: dismiss()
            case .locked: showHelp = true
            }
        } content: {
            Group {
                switch flow.stage {
                case .form: form
                case .code:
                    SheetBlock {
                        OneTimeCodeEntry(destination: flow.sentTo, code: flow.code, onCode: flow.enterCode,
                                         busy: flow.busy, error: flow.error, needsHelp: flow.needsHelp,
                                         helpTopic: L("Password change"),
                                         hint: L("Check your inbox, and your spam folder. It's the code that confirms it's you."),
                                         resendIn: flow.resendIn, editTitle: L("Edit password"),
                                         onEdit: { flow.edit() },
                                         onResend: { Task { await flow.resend() } })
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                case .done:
                    CodeVerifiedCard(title: L("Password updated"), detail: L("Use it next time you log in on another device."))
                case .locked: CodeLockedCard(message: flow.error)
                }
            }
            .animation(Motion.snappy, value: flow.stage)
        }
        .onChange(of: new) { if flow.stage == .form { flow.error = nil } }
        .onChange(of: confirm) { if flow.stage == .form { flow.error = nil } }
        .sheet(isPresented: $showHelp) { Group { SupportSheet(topic: L("Password change")) }.sheetSurface() }
    }

    private var form: some View {
        SheetBlock {
            DrafftField(title: L("New password"), text: $new, prompt: L("New password"),
                        isSecure: true, contentType: .newPassword)
            VStack(alignment: .leading, spacing: DS.Space.xs + 2) {
                ForEach(PasswordRule.all) { rule in
                    let ok = rule.test(new)
                    HStack(spacing: DS.Space.sm) {
                        // The one check mark in the app (bigger than the label, easy to read at a glance).
                        CheckDisc(isOn: ok, size: 22)
                        Text(rule.label).foregroundStyle(ok ? DS.Palette.ink : DS.Palette.body)
                    }
                        // One weight, done or not: the disc and the ink say it, the line never widens.
                        .font(.footnote.weight(.medium))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(rule.label)
                        .accessibilityValue(ok ? "Done" : "Not yet")
                }
            }
            DrafftField(title: L("Confirm new password"), text: $confirm, prompt: L("Type it again"),
                        isSecure: true,
                        error: !confirm.isEmpty && confirm != new ? L("Doesn't match yet.") : nil,
                        contentType: .newPassword, submitLabel: .send,
                        onSubmit: { if valid { send() } })
        }
    }

    private func send() {
        let password = new
        // Rules the server holds that the form can't check: back to the form to pick another.
        flow.formProblems = [.samePassword, .weakPassword]
        Task {
            await flow.send(to: app.email) {
                try await Backend.shared.sendReauthenticationCode()
            } verify: { code in
                try await Backend.shared.updatePassword(password, code: code)
            }
        }
    }
}

// MARK: - Export

struct ExportDataSheet: View {
    @Environment(AppModel.self) private var app
    @State private var sending = false
    @State private var exportError: String?

    private var included: [(icon: String, title: String, detail: String)] { [
        ("user-rounded", L("Profile"), L("Name, bio, sports, prompts, lifestyle")),
        ("gallery-wide", L("Photos & voice"), L("Everything you've uploaded")),
        ("dialog-2", L("Messages"), L("Your conversations with matches")),
        ("calendar", L("Sessions"), L("Invites you sent and received")),
        ("heart", L("Likes & matches"), L("Who you liked and matched with"))
    ] }

    private var requested: Date? { app.dataExportRequestedAt }

    var body: some View {
        AccountSheet(title: L("Export my data"),
                     actionTitle: requested == nil ? L("Email me my export") : L("Export requested"),
                     actionIcon: requested == nil ? "letter" : "check",
                     enabled: requested == nil && !sending, loading: sending, error: exportError) {
            sending = true
            exportError = nil
            Task {
                defer { sending = false }
                do {
                    // The server keeps one open request and says when it was made.
                    _ = try await Backend.shared.rpc("request_data_export", [:])
                    Haptics.success()
                    withAnimation(Motion.bouncy) { app.dataExportRequestedAt = .now }
                } catch {
                    Haptics.warning()
                    exportError = L("Your request couldn't be sent. Check your connection and try again.")
                }
            }
        } content: {
            if let requested {
                SheetBlock {
                    Label("Check your inbox", image: "letter-opened")
                        .font(.headline)
                        .foregroundStyle(DS.Palette.ink)
                    Text("We're preparing your export. A download link goes to \(app.email), usually within 24 hours of \(requested.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(.app))). The link works for 7 days.")
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity)
            } else {
                SheetBlock {
                    Text(branded: L("Get a copy of everything you've shared on drafft. We'll email you a download link to a file you can keep or open elsewhere."), font: .subheadline)
                        .foregroundStyle(DS.Palette.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            SheetBlock(title: L("What's included")) {
                VStack(spacing: DS.Space.md) {
                    ForEach(included, id: \.title) { item in
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
                            Image(item.icon)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(DS.Palette.ink)
                                .frame(width: 32, height: 32)
                                .background(DS.Palette.canvasSoft, in: .circle)
                                .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 5 }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(DS.Palette.ink)
                                Text(item.detail).font(.footnote).foregroundStyle(DS.Palette.body)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Delete

struct DeleteAccountSheet: View {
    /// Opened from the sensitive data consent: drafft can't work without the gender, so withdrawing
    /// the consent is deleting the account. The page says so, and offers no pause (it keeps the data)
    /// and no reasons to pick (the reason is known).
    var withdrawsConsent = false
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var reason: String?
    @State private var understood = false
    @State private var loading = false
    @State private var failure: String?
    @State private var managingSubscription = false

    private var showsSubscriptionNotice: Bool {
        let renewal: SubscriptionNotice.Renewal = app.subscription.map { $0.willRenew ? .renews : .ends } ?? .unknown
        return SubscriptionNotice.showsOnDelete(renewal, isPremium: app.isPremium)
    }

    private var reasons: [String] { [L("I met someone"), L("I need a break"), L("Not enough people nearby"), L("Something else")] }

    var body: some View {
        AccountSheet(title: withdrawsConsent ? L("Sensitive data consent") : L("Delete account"),
                     actionTitle: L("Delete my account"), actionIcon: "trash-bin-minimalistic",
                     destructive: true, enabled: understood, loading: loading,
                     error: failure) {
            loading = true
            failure = nil
            Task {
                do {
                    try await app.deleteAccount()
                    Haptics.success()
                    dismiss()
                } catch Backend.BackendError.signedOut {
                    Haptics.warning()
                    loading = false
                    failure = L("You're logged out, so nothing was deleted. Log in again, then delete your account.")
                } catch {
                    Haptics.warning()
                    loading = false
                    failure = L("We couldn't delete your account. Check your connection and try again.")
                }
            }
        } content: {
            if withdrawsConsent {
                consentBlock
            } else {
                SheetBlock {
                    Text("Here's what deleting removes.")
                        .font(.display(26, relativeTo: .title2))
                        .foregroundStyle(DS.Palette.ink)
                    Text("Deleting removes your profile, photos, matches and messages for good. Your matches won't be able to reach you.")
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Billing belongs to the App Store: deleting the account leaves a renewing subscription on.
            // Also shown while the App Store's answer is unknown and the server says drafft tempo.
            if showsSubscriptionNotice {
                SheetBlock(title: L("Your subscription")) {
                    Text(branded: L("Deleting your account doesn't cancel drafft tempo. Cancel it in the App Store to stop it renewing."),
                         font: .subheadline)
                        .foregroundStyle(DS.Palette.body)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Manage subscription") {
                        Haptics.tap()
                        managingSubscription = true
                    }
                    .buttonStyle(.drafftSecondary)
                }
            }

            if !withdrawsConsent {
                pauseBlock
                reasonsBlock
            }

            SheetBlock {
                Toggle(isOn: $understood.animation(Motion.snappy)) {
                    Text("I understand my account will be deleted for good.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .tint(DS.Palette.negative)
                .onChange(of: understood) { Haptics.select() }
            }
        }
        // On the sheet itself, not the subscription block: the refresh can take the block away
        // while Apple's sheet is still up.
        .manageSubscriptionsSheet(isPresented: $managingSubscription)
        // Cancelling there makes no transaction, so RevenueCat's stream (DrafftApp) can lag behind:
        // read the App Store again once Apple's sheet closes.
        .onChange(of: managingSubscription) { _, open in
            guard !open else { return }
            Task { await app.refreshSubscription { sub in withAnimation(Motion.snappy) { app.subscription = sub } } }
        }
    }

    private var reasonsBlock: some View {
        SheetBlock(title: L("Why are you leaving?")) {
            FlowLayout(spacing: DS.Space.sm) {
                ForEach(reasons, id: \.self) { r in
                    let on = reason == r
                    Button {
                        Haptics.select()
                        withAnimation(Motion.snappy) { reason = on ? nil : r }
                    } label: {
                        Text(r)
                            .font(.footnote.weight(.semibold))
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
            Text(branded: L("Optional. It helps us make drafft better."), font: .footnote)
                .foregroundStyle(DS.Palette.mute)
        }
    }

    private var consentBlock: some View {
        SheetBlock {
            Text("Withdrawing your consent means deleting your account.")
                .font(.display(26, relativeTo: .title2))
                .foregroundStyle(DS.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Group {
                Text(branded: L("drafft needs your gender and the genders you want to see to suggest anyone."), font: .subheadline)
                Text("Deleting removes them with your profile, photos, matches and messages, for good.")
                    .font(.subheadline)
            }
            .foregroundStyle(DS.Palette.body)
            .fixedSize(horizontal: false, vertical: true)
            Button {
                Haptics.tap()
                openURL(LegalDoc.sensitiveData(), prefersInApp: true)
            } label: {
                Label("How drafft uses this data", image: "arrow-right-up")
            }
            .buttonStyle(.drafftTertiary)
        }
    }

    private var pauseBlock: some View {
        SheetBlock(title: L("Just need a break?")) {
            Text("Pausing hides you from Discover and keeps your matches and chats.")
                .font(.subheadline)
                .foregroundStyle(DS.Palette.body)
            Button {
                Haptics.success()
                app.profilePaused = true
                dismiss()
            } label: {
                Label(app.profilePaused ? "Your profile is paused" : "Pause my profile instead", image: "pause")
            }
            .buttonStyle(.drafftSecondary)
            .disabled(app.profilePaused)
        }
    }
}

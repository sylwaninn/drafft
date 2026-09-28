import SwiftUI

/// The 6-digit code step, shared by every check (SMS at sign-up and in You, email for a new address
/// or a new password): where it went with a way to change it, six boxes, the status line, resend.
struct OneTimeCodeEntry<Accessory: View>: View {
    /// "+33 6 12 34 56 78" or "you@example.com".
    let destination: String
    let code: String
    let onCode: (String) -> Void
    var busy: Bool
    var error: String?
    var needsHelp = false
    var helpTopic: String
    /// Under the boxes when nothing's wrong ("Check your messages…").
    var hint: String
    var resendIn: Int
    var editTitle = L("Change")
    var boxFill: Color = DS.Palette.field
    let onEdit: () -> Void
    let onResend: () -> Void
    /// Between the status line and Resend (the demo panel).
    @ViewBuilder var accessory: Accessory

    @FocusState private var focused: Bool
    @State private var fieldWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Code sent to \(destination)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(editTitle, action: onEdit)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.accentInk)
                    .buttonStyle(.textLink)
                    .disabled(busy)
            }

            // Six boxes drawn behind one plain, visible TextField whose digits are spaced into them.
            // iOS only autofills the code tapped above the keyboard into a field it can see: never
            // a hidden, transparent or covered one.
            ZStack(alignment: .leading) {
                HStack(spacing: DS.Space.sm) {
                    ForEach(0..<6, id: \.self) { i in
                        let current = i == code.count && focused
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .fill(boxFill)
                            .overlay {
                                RoundedRectangle(cornerRadius: DS.Radius.md)
                                    .strokeBorder(error != nil ? DS.Palette.negative
                                                  : (current ? DS.Palette.ink : DS.Palette.ink.opacity(0.2)),
                                                  lineWidth: current || error != nil ? 2 : 1)
                            }
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                TextField("", text: Binding(get: { code }, set: onCode))
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focused)
                    .font(.custom(DisplayFont.extraBold, fixedSize: CodeDigits.size).monospacedDigit())
                    .tracking(digitLayout.tracking)
                    .foregroundStyle(DS.Palette.ink)
                    // The caret sits right after the last digit, in the previous box: drawn in the
                    // box's own colour, so it doesn't show (the current box's outline says where the
                    // next digit goes). Opaque on purpose: iOS won't autofill a field with a clear tint.
                    .tint(boxFill)
                    .padding(.leading, digitLayout.inset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .accessibilityLabel("Verification code")
                    .revealsOnFocus(focused)
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .contentShape(.rect)
            .onTapGesture { focused = true }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { fieldWidth = $0 }

            // While checking, the status line says so (the boxes keep the typed code).
            if busy {
                HStack(spacing: DS.Space.xs) {
                    ProgressView().controlSize(.small).tint(DS.Palette.ink)
                    Text("Checking the code…").font(.footnote).foregroundStyle(DS.Palette.body)
                }
                .frame(minHeight: 18)
            } else if let error {
                VStack(alignment: .leading, spacing: 0) {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(DS.Palette.negative)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    if needsHelp { GetHelpButton(topic: helpTopic) }
                }
            } else {
                // Body grey: mute is under 4.5:1 on the sage page.
                Text(hint).font(.footnote).foregroundStyle(DS.Palette.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            accessory

            Button(action: onResend) {
                Text(resendIn > 0 ? "Resend code in 0:\(String(format: "%02d", resendIn))" : "Resend code")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(resendIn > 0 ? DS.Palette.body : DS.Palette.accentInk)
                    .rollingDigits(wording: resendIn > 0, countsDown: true)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .disabled(resendIn > 0 || busy)
        }
        .animation(Motion.snappy, value: error)
        // The step appears once a code was asked for: the keyboard comes up with it, once the step has
        // faded in. Focused mid-fade (still nearly transparent), iOS never fills in the code tapped
        // above the keyboard.
        .task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            focused = true
        }
    }

    /// Each digit's advance becomes a box plus the gap, and the first one is centred in the first box.
    private var digitLayout: (tracking: CGFloat, inset: CGFloat) {
        let box = max(0, (fieldWidth - DS.Space.sm * 5) / 6)
        return (box + DS.Space.sm - CodeDigits.advance, max(0, (box - CodeDigits.advance) / 2))
    }
}

/// The code's digits: the display font at a fixed size, so six always fit their boxes.
private enum CodeDigits {
    /// Points.
    static let size: CGFloat = 26

    /// The width of one tabular digit in the display font.
    static let advance: CGFloat = {
        let base = UIFont(name: DisplayFont.extraBold, size: size) ?? .systemFont(ofSize: size, weight: .heavy)
        let tabular = base.fontDescriptor.addingAttributes([.featureSettings: [[
            UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
            UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector
        ]]])
        return ("0" as NSString).size(withAttributes: [.font: UIFont(descriptor: tabular, size: size)]).width
    }()
}

extension OneTimeCodeEntry where Accessory == EmptyView {
    init(destination: String, code: String, onCode: @escaping (String) -> Void, busy: Bool, error: String?,
         needsHelp: Bool = false, helpTopic: String, hint: String, resendIn: Int,
         editTitle: String = L("Change"), boxFill: Color = DS.Palette.field,
         onEdit: @escaping () -> Void, onResend: @escaping () -> Void) {
        self.init(destination: destination, code: code, onCode: onCode, busy: busy, error: error,
                  needsHelp: needsHelp, helpTopic: helpTopic, hint: hint, resendIn: resendIn,
                  editTitle: editTitle, boxFill: boxFill, onEdit: onEdit, onResend: onResend) { EmptyView() }
    }
}

/// The check went through: a lime disc and what's now on the account.
struct CodeVerifiedCard: View {
    let title: String
    let detail: String
    var fill: Surface = DS.Palette.canvas

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: "checkmark")
                .font(.body.weight(.heavy))
                .foregroundStyle(DS.Palette.onLime)
                .frame(width: 44, height: 44)
                .background(DS.Palette.lime, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(DS.Palette.ink)
                Text(detail).font(.subheadline.monospacedDigit()).foregroundStyle(DS.Palette.body)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.lg)
        .background(fill, in: .rect(cornerRadius: DS.Radius.xl))
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }
}

/// Too many wrong codes: paused until the team unlocks it (the footer offers Get help).
struct CodeLockedCard: View {
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Label("Verification paused", systemImage: "lock.fill")
                .font(.headline)
                .foregroundStyle(DS.Palette.negative)
            Text(message ?? L("Too many tries."))
                .font(.subheadline)
                .foregroundStyle(DS.Palette.body)
            Text("Our team can unlock it for you.")
                .font(.subheadline)
                .foregroundStyle(DS.Palette.body)
        }
        .padding(DS.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
    }
}

// MARK: - Email code

/// A check by email: fill the form, a 6-digit code goes out, typing the sixth digit checks it.
/// The host says what sending and checking mean (a new address, a new password).
@MainActor
@Observable
final class EmailCodeModel {
    enum Stage: Equatable { case form, code, done, locked }

    private(set) var stage: Stage = .form
    private(set) var code = ""
    private(set) var busy = false
    /// On the form while sending, under the boxes once the code is out.
    var error: String?
    private(set) var needsHelp = false
    private(set) var resendIn = 0
    private(set) var attemptsLeft = 5
    /// When the last code went out: Supabase answers the same for a mistyped code and an old one, so the
    /// time says which it was.
    private var sentAt = Date.distantPast
    private(set) var sentTo = ""

    /// Host wording for a problem ("Your password is incorrect." rather than the log-in message).
    var messages: [AuthProblem: String] = [:]
    /// Problems with what was typed on the form, not the code: they send the person back to it.
    var formProblems: Set<AuthProblem> = []

    private var sender: (() async throws -> Void)?
    private var checker: ((String) async throws -> Void)?
    private var timer: Task<Void, Never>?

    /// Sends the code, then waits for it. `send` throws to keep the form up with its error.
    func send(to address: String, send: @escaping () async throws -> Void,
              verify: @escaping (String) async throws -> Void) async {
        guard !busy else { return }
        busy = true
        error = nil
        do {
            try await send()
            sender = send
            checker = verify
            sentTo = address
            code = ""
            attemptsLeft = 5
            stage = .code
            startResendTimer()
            Haptics.success()
        } catch {
            self.error = message(for: AuthProblem(error))
            Haptics.warning()
        }
        busy = false
    }

    /// The code already went out with something else (sign-up): wait for it, `resend` sends another.
    func awaitCode(sentTo address: String, resend: @escaping () async throws -> Void,
                   verify: @escaping (String) async throws -> Void) {
        sender = resend
        checker = verify
        sentTo = address
        code = ""
        attemptsLeft = 5
        stage = .code
        startResendTimer()
    }

    func enterCode(_ raw: String) {
        let clean = String(raw.filter(\.isNumber).prefix(6))
        let wasShort = code.count < 6
        code = clean
        if !code.isEmpty { error = nil }
        if code.count == 6 && wasShort && stage == .code { Task { await verify() } }
    }

    func verify() async {
        guard code.count == 6, !busy, let checker else { return }
        busy = true
        error = nil
        do {
            try await checker(code)
            stage = .done
            timer?.cancel()
            Haptics.success()
        } catch {
            code = ""
            Haptics.warning()
            let problem = AuthProblem(error)
            if problem == .wrongCode && Date.now.timeIntervalSince(sentAt) > BackendConfig.emailCodeLifetime {
                // Past its lifetime: not a typo, and not a try used up.
                self.error = L("This code has expired. Send a new one.")
            } else if problem == .wrongCode {
                attemptsLeft -= 1
                if attemptsLeft <= 0 {
                    stage = .locked
                    timer?.cancel()
                    self.error = L("Too many wrong codes. For your security, this change is paused.")
                    needsHelp = true
                } else {
                    self.error = attemptsLeft == 1 ? L("Wrong code. 1 try left.")
                        : L("Wrong code. \(attemptsLeft) tries left.")
                }
            } else if formProblems.contains(problem) {
                edit(error: message(for: problem))
            } else {
                self.error = message(for: problem)
            }
        }
        busy = false
    }

    func resend() async {
        guard resendIn == 0, !busy, let sender else { return }
        busy = true
        error = nil
        do {
            try await sender()
            code = ""
            startResendTimer()
            Haptics.success()
        } catch {
            self.error = message(for: AuthProblem(error))
            Haptics.warning()
        }
        busy = false
    }

    /// Back to the form (Change, or the server turned the new value down).
    func edit(error: String? = nil) {
        timer?.cancel()
        resendIn = 0
        stage = .form
        code = ""
        self.error = error
        needsHelp = false
    }

    private func message(for problem: AuthProblem) -> String { messages[problem] ?? problem.message }

    /// A code just went out: its lifetime and the Resend countdown start now.
    private func startResendTimer() {
        timer?.cancel()
        sentAt = .now
        resendIn = 30
        timer = Task { [weak self] in
            while let self, self.resendIn > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self.resendIn -= 1
            }
        }
    }
}

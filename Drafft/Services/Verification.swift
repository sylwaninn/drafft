import Foundation
import Observation

// MARK: - Contracts (to be backed by the real API later)

enum VerificationError: Error, Equatable {
    case invalidNumber, sendFailed, wrongCode, expired, tooManyAttempts, network
}

protocol PhoneVerifying: Sendable {
    /// Texts a 6-digit code to an E.164 number.
    func sendCode(to e164: String) async throws
    func verify(code: String, for e164: String) async throws
}

// MARK: - Demo implementations (no backend yet)

/// Demo stand-in. The outcomes are chosen in the demo panels (PhoneVerificationModel.demoSend / demoCode).
struct DemoPhoneVerifier: PhoneVerifying {
    func sendCode(to e164: String) async throws {
        try? await Task.sleep(for: .milliseconds(400))
        if e164.hasSuffix("0000") { throw VerificationError.sendFailed }
    }

    func verify(code: String, for e164: String) async throws {
        try? await Task.sleep(for: .milliseconds(400))
        switch code {
        case "123456": return
        case "000000": throw VerificationError.expired
        default: throw VerificationError.wrongCode
        }
    }
}

/// The real one: Supabase Auth phone change. Sets the number on the account once the code checks
/// out, at sign-up as in You. Needs an SMS provider on the project (not set up yet).
struct BackendPhoneVerifier: PhoneVerifying {
    func sendCode(to e164: String) async throws {
        do { try await Backend.shared.updatePhone(e164) } catch { throw VerificationError(error) }
    }

    func verify(code: String, for e164: String) async throws {
        do { try await Backend.shared.confirmPhoneChange(e164, code: code) } catch { throw VerificationError(error) }
    }
}

extension VerificationError {
    init(_ error: Error) {
        if error is URLError { self = .network; return }
        switch AuthProblem(error) {
        case .wrongCode: self = .wrongCode
        case .offline: self = .network
        default: self = .sendFailed
        }
    }
}

// MARK: - Phone

struct PhoneCountry: Hashable, Identifiable {
    let flag: String, region: String, dial: String
    let digits: ClosedRange<Int>
    let example: String
    var id: String { region }
    /// Country name in the app's language.
    var name: String { Locale.app.localizedString(forRegionCode: region) ?? region }

    static let all: [PhoneCountry] = [
        .init(flag: "🇫🇷", region: "FR", dial: "+33", digits: 9...9, example: "6 12 34 56 78"),
        .init(flag: "🇧🇪", region: "BE", dial: "+32", digits: 8...9, example: "470 12 34 56"),
        .init(flag: "🇨🇭", region: "CH", dial: "+41", digits: 9...9, example: "78 123 45 67"),
        .init(flag: "🇱🇺", region: "LU", dial: "+352", digits: 8...9, example: "621 123 456"),
        .init(flag: "🇬🇧", region: "GB", dial: "+44", digits: 10...10, example: "7400 123456"),
        .init(flag: "🇪🇸", region: "ES", dial: "+34", digits: 9...9, example: "612 34 56 78"),
        .init(flag: "🇮🇹", region: "IT", dial: "+39", digits: 9...10, example: "312 345 6789"),
        .init(flag: "🇩🇪", region: "DE", dial: "+49", digits: 10...11, example: "1512 3456789"),
        .init(flag: "🇺🇸", region: "US", dial: "+1", digits: 10...10, example: "201 555 0123"),
        .init(flag: "🇨🇦", region: "CA", dial: "+1", digits: 10...10, example: "506 234 5678")
    ]
}

/// Front-end state machine for phone verification: number, code, verified, or locked.
@MainActor
@Observable
final class PhoneVerificationModel {
    enum Stage: Equatable { case enterNumber, enterCode, verified, locked }

    private(set) var stage: Stage = .enterNumber
    var country = PhoneCountry.all[0]
    var number = "" { didSet { error = nil } }
    /// Set through `enterCode(_:)` (digits only, max 6). No didSet rewriting itself here: with
    /// @Observable that recursed forever and crashed the app when a code was sent.
    private(set) var code = ""
    /// Demo only: what the next "send" and the next code do, to try every state.
    enum DemoSend: String, CaseIterable { case works = "Sends", fails = "Fails" }
    enum DemoCode: String, CaseIterable { case accepted = "Accepted", wrong = "Wrong", expired = "Expired" }
    var demoSend: DemoSend = .works
    var demoCode: DemoCode = .accepted
    var isDemo: Bool { service is DemoPhoneVerifier }
    private(set) var busy = false
    private(set) var error: String?
    /// Shown with a L("Get help") button (sending failed, too many tries).
    private(set) var needsHelp = false
    private(set) var resendIn = 0
    private(set) var attemptsLeft = 5
    private(set) var verifiedNumber: String?
    /// A number that doesn't count as new (changing: the current one).
    var currentNumber: String?

    private let service: PhoneVerifying
    private var timer: Task<Void, Never>?
    /// When the last code went out: Supabase answers the same for a mistyped code and an old one, so the
    /// time says which it was.
    private var sentAt = Date.distantPast

    /// Sign-up and You share this: flip `BackendConfig.smsEnabled` once the project has an SMS provider.
    init(service: PhoneVerifying = BackendConfig.smsEnabled ? BackendPhoneVerifier() as PhoneVerifying : DemoPhoneVerifier()) {
        self.service = service
    }

    func enterCode(_ raw: String) {
        let clean = String(raw.filter(\.isNumber).prefix(6))
        let wasShort = code.count < 6
        code = clean
        if !code.isEmpty { error = nil }
        if code.count == 6 && wasShort && stage == .enterCode { Task { await verify() } }
    }

    private var nationalDigits: String {
        var d = number.filter(\.isNumber)
        if d.hasPrefix("0") { d.removeFirst() } // "06 12…" typed the French way
        return d
    }
    var e164: String { country.dial + nationalDigits }
    var numberValid: Bool { country.digits.contains(nationalDigits.count) }
    var isSameAsCurrent: Bool { currentNumber == e164 }

    /// "+33 6 12 34 56 78"
    var displayNumber: String {
        if let restoredDisplay, number.isEmpty { return restoredDisplay }
        let d = nationalDigits
        guard let first = d.first else { return country.dial }
        var pairs: [String] = [String(first)]
        var rest = Substring(d.dropFirst())
        while !rest.isEmpty { pairs.append(String(rest.prefix(2))); rest = rest.dropFirst(2) }
        return "\(country.dial) \(pairs.joined(separator: " "))"
    }

    var primaryTitle: String {
        switch stage {
        case .enterNumber: L("Send code")
        case .enterCode: L("Verify")
        case .verified: L("Continue")
        case .locked: L("Get help")
        }
    }

    var primaryEnabled: Bool {
        switch stage {
        case .enterNumber: numberValid && !isSameAsCurrent && !busy
        case .enterCode: code.count == 6 && !busy
        case .verified, .locked: true
        }
    }

    /// Why the primary action is disabled, or what happens next.
    var hint: String? {
        switch stage {
        case .enterNumber:
            if number.isEmpty { return L("Enter your mobile number.") }
            if isSameAsCurrent { return L("That's already your number.") }
            if !numberValid { return L("That number looks incomplete.") }
            return L("We'll text a 6-digit code to \(displayNumber).")
        case .enterCode: return code.count < 6 ? L("Enter the 6-digit code.") : nil
        case .verified, .locked: return nil
        }
    }

    func sendCode() async {
        guard numberValid else { error = L("Check the number, it looks incomplete."); return }
        busy = true
        error = nil
        needsHelp = false
        do {
            if isDemo {
                try? await Task.sleep(for: .milliseconds(400))
                if demoSend == .fails { throw VerificationError.sendFailed }
            } else {
                try await service.sendCode(to: e164)
            }
            code = ""
            stage = .enterCode
            startResendTimer()
            Haptics.success()
        } catch {
            self.error = L("We couldn't text this number. Check it, or get help if it keeps failing.")
            needsHelp = true
            Haptics.warning()
        }
        busy = false
    }

    func verify() async {
        guard code.count == 6, !busy else { return }
        busy = true
        error = nil
        do {
            if isDemo {
                try? await Task.sleep(for: .milliseconds(300))
                switch demoCode {
                case .accepted: break
                case .wrong: throw VerificationError.wrongCode
                case .expired: throw VerificationError.expired
                }
            } else {
                do {
                    try await service.verify(code: code, for: e164)
                } catch VerificationError.wrongCode where Date.now.timeIntervalSince(sentAt) > BackendConfig.smsCodeLifetime {
                    throw VerificationError.expired
                }
            }
            verifiedNumber = e164
            stage = .verified
            timer?.cancel()
            Haptics.success()
        } catch VerificationError.expired {
            error = L("This code has expired. Send a new one.")
            code = ""
            Haptics.warning()
        } catch {
            attemptsLeft -= 1
            code = ""
            Haptics.warning()
            if attemptsLeft <= 0 {
                stage = .locked
                self.error = L("Too many wrong codes. For your security, verification is paused.")
                needsHelp = true
            } else {
                self.error = attemptsLeft == 1 ? L("Wrong code. 1 try left.") : L("Wrong code. \(attemptsLeft) tries left.")
            }
        }
        busy = false
    }

    func resend() async {
        guard resendIn == 0 else { return }
        await sendCode()
    }

    /// Resuming a sign-up whose number was already verified.
    func restoreVerified(_ display: String) {
        verifiedNumber = display
        restoredDisplay = display
        stage = .verified
    }
    private(set) var restoredDisplay: String?

    func changeNumber() {
        timer?.cancel()
        stage = .enterNumber
        code = ""
        error = nil
        needsHelp = false
    }

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

// MARK: - Face on the main photo

import Vision
import UIKit

/// On-device check (Apple Vision) that a photo shows a face big enough to be recognised.
enum FaceCheck {
    enum Result: Equatable { case face, noFace, tooSmall }

    static func check(photo path: String) async -> Result {
        let image: UIImage? = path.hasPrefix("/") ? UIImage(contentsOfFile: path) : UIImage(named: path)
        guard let cg = image?.cgImage else { return .noFace }
        return await Task.detached(priority: .userInitiated) {
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
            try? handler.perform([request])
            let faces = request.results ?? []
            guard let biggest = faces.map({ $0.boundingBox.width * $0.boundingBox.height }).max() else { return Result.noFace }
            // At least ~2% of the frame: a face you could actually recognise.
            return biggest >= 0.02 ? .face : .tooSmall
        }.value
    }
}

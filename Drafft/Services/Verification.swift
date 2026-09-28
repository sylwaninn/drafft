import Foundation
import Observation
import Supabase

// MARK: - Contracts

enum VerificationError: Error, Equatable {
    case invalidNumber, sendFailed, wrongCode, expired, tooManyAttempts, network, numberTaken
}

protocol PhoneVerifying: Sendable {
    /// Texts a 6-digit code to an E.164 number.
    func sendCode(to e164: String) async throws
    func verify(code: String, for e164: String) async throws
    /// The number already verified on the account (E.164), if any.
    func verifiedNumber() async -> String?
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

    /// Read from the server (a number verified on another device, or before a reinstall), else from
    /// the saved session. Supabase Auth keeps it without the "+".
    func verifiedNumber() async -> String? {
        let auth = Backend.shared.client.auth
        let fresh = try? await auth.user()
        guard let user = fresh ?? auth.currentUser, user.phoneConfirmedAt != nil,
              let phone = user.phone, !phone.isEmpty else { return nil }
        return "+" + phone.filter(\.isNumber)
    }
}

extension VerificationError {
    init(_ error: Error) {
        if error is URLError { self = .network; return }
        if (error as? AuthError)?.errorCode == .phoneExists { self = .numberTaken; return }
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

    /// "+33 6 12 34 56 78": the dial code, then the national digits by pairs after the first.
    static func format(dial: String, national: String) -> String {
        guard let first = national.first else { return dial }
        var pairs: [String] = [String(first)]
        var rest = Substring(national.dropFirst())
        while !rest.isEmpty { pairs.append(String(rest.prefix(2))); rest = rest.dropFirst(2) }
        return "\(dial) \(pairs.joined(separator: " "))"
    }

    /// The account's number as Supabase Auth keeps it ("33612345678"), written like the app writes it.
    static func display(_ stored: String) -> String {
        let digits = stored.filter(\.isNumber)
        guard let country = all.filter({ digits.hasPrefix($0.dial.dropFirst()) }).max(by: { $0.dial.count < $1.dial.count })
        else { return "+" + digits }
        return format(dial: country.dial, national: String(digits.dropFirst(country.dial.count - 1)))
    }
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

    /// Sign-up and You share this.
    init(service: PhoneVerifying = BackendPhoneVerifier()) {
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
        return PhoneCountry.format(dial: country.dial, national: nationalDigits)
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

    func sendCode() async {
        guard numberValid else { error = L("Check the number, it looks incomplete."); return }
        busy = true
        error = nil
        needsHelp = false
        // Already the account's verified number (a sign-up started over, a reinstall): nothing to
        // send, Supabase wouldn't text it anyway. The step is done.
        if await service.verifiedNumber() == e164 {
            verifiedNumber = e164
            stage = .verified
            busy = false
            Haptics.success()
            return
        }
        do {
            try await service.sendCode(to: e164)
            code = ""
            stage = .enterCode
            startResendTimer()
            Haptics.success()
        } catch VerificationError.numberTaken {
            self.error = L("This number is already used by another drafft account.")
            needsHelp = true
            Haptics.warning()
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
            do {
                try await service.verify(code: code, for: e164)
            } catch VerificationError.wrongCode where Date.now.timeIntervalSince(sentAt) > BackendConfig.smsCodeLifetime {
                throw VerificationError.expired
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
        guard let biggest = await faces(in: cg).map({ $0.width * $0.height }).max() else { return .noFace }
        // At least ~2% of the frame: a face you could actually recognise.
        return biggest >= 0.02 ? .face : .tooSmall
    }

    /// The faces Vision finds, as boxes in 0...1 of the upright image (origin at the bottom left).
    static func faces(in image: CGImage, orientation: CGImagePropertyOrientation = .up) async -> [CGRect] {
        await Task.detached(priority: .userInitiated) {
            let request = VNDetectFaceRectanglesRequest()
            try? VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
            return (request.results ?? []).map(\.boundingBox)
        }.value
    }
}

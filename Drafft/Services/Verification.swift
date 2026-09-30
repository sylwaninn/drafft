import Foundation
import Observation
import PhoneNumberKit
import Supabase

// MARK: - Contracts

enum VerificationError: Error, Equatable {
    case invalidNumber, sendFailed, wrongCode, expired, tooManyAttempts, network, numberTaken
    /// phone-code's refusals: the account's email isn't confirmed, too many codes, not a mobile line,
    /// the line couldn't be checked (Twilio Lookup down: nothing is sent).
    case emailUnconfirmed, tooManyCodes, unsupportedLine, checkUnavailable

    /// The words under the number field.
    var message: String {
        switch self {
        case .numberTaken: L("This number is already used by another drafft account.")
        case .emailUnconfirmed: L("Confirm your email first, then add your number.")
        case .tooManyCodes: L("Too many codes sent. Try again later.")
        case .invalidNumber: L("That doesn't look like a mobile number.")
        case .unsupportedLine: L("This number can't get codes. Use a mobile number.")
        case .checkUnavailable: L("We couldn't check this number right now. Try again in a moment.")
        case .network: L("Couldn't connect. Check your connection and try again.")
        default: L("We couldn't text this number. Check it, or get help if it keeps failing.")
        }
    }
}

protocol PhoneVerifying: Sendable {
    /// Texts a 6-digit code to an E.164 number.
    func sendCode(to e164: String) async throws
    func verify(code: String, for e164: String) async throws
    /// The number already verified on the account (E.164), if any.
    func verifiedNumber() async -> String?
}

/// The real one: the phone-code function, then Supabase Auth's phone change. Sets the number on the
/// account once the code checks out, at sign-up as in You.
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
    /// phone-code's stable codes (backend _shared/phone_code.ts).
    private static let serverCodes: [String: VerificationError] = [
        "email_unconfirmed": .emailUnconfirmed,
        "sms_limit": .tooManyCodes,
        "phone_invalid": .invalidNumber,
        "phone_unsupported": .unsupportedLine,
        "phone_taken": .numberTaken,
        "phone_check_unavailable": .checkUnavailable
    ]

    init(_ error: Error) {
        if error is URLError { self = .network; return }
        if (error as? AuthError)?.errorCode == .phoneExists { self = .numberTaken; return }
        if case let Backend.BackendError.http(_, code) = error {
            self = Self.serverCodes[code] ?? .sendFailed
            return
        }
        switch AuthProblem(error) {
        case .wrongCode: self = .wrongCode
        case .offline: self = .network
        default: self = .sendFailed
        }
    }
}

// MARK: - Phone

/// Front-end state machine for phone verification: number, code, verified, or locked.
@MainActor
@Observable
final class PhoneVerificationModel {
    enum Stage: Equatable { case enterNumber, enterCode, verified, locked }

    private(set) var stage: Stage = .enterNumber
    var country = PhoneCountry.initial { didSet { parse() } }
    /// What the field shows. Typed or pasted the international way, the country follows at once and
    /// the field keeps the national part ("+33 6 12…" becomes France and "06 12…").
    var number: String {
        get { typed }
        set {
            error = nil
            if let found = PhoneCountry.international(newValue, from: country) {
                typed = found.national
                if found.country != country { country = found.country } else { parse() }
            } else {
                typed = newValue
                parse()
            }
        }
    }
    /// Set through `number` only: a didSet rewriting the field here recursed with @Observable.
    private var typed = ""
    /// The typed number, once it's a mobile number of the country.
    private var parsed: PhoneNumber?
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

    private func parse() {
        parsed = PhoneCountry.mobileNumber(number, in: country)
        // A shared calling code: the complete number says which country it is (+1 787 is Puerto Rico).
        if let parsed, let region = PhoneCountry.phoneNumbers.getRegionCode(of: parsed), region != country.region,
           let exact = PhoneCountry.country(region) {
            country = exact
        }
    }

    var e164: String {
        parsed.map { PhoneCountry.phoneNumbers.format($0, toType: .e164) } ?? country.dial + number.filter(\.isNumber)
    }
    var numberValid: Bool { parsed != nil }
    var isSameAsCurrent: Bool { currentNumber == e164 }

    /// "+33 6 12 34 56 78"
    var displayNumber: String {
        if let restoredDisplay, number.isEmpty { return restoredDisplay }
        return parsed.map { PhoneCountry.phoneNumbers.format($0, toType: .international) } ?? e164
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
        guard numberValid else { error = VerificationError.invalidNumber.message; return }
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
        } catch {
            let failure = error as? VerificationError ?? .sendFailed
            self.error = failure.message
            // Nothing to fix on the number there: waiting, or confirming the email, is the way.
            needsHelp = ![.tooManyCodes, .emailUnconfirmed, .network, .checkUnavailable].contains(failure)
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
import ImageIO

/// On-device check (Apple Vision) that a photo shows a face big enough to be recognised.
enum FaceCheck {
    enum Result: Equatable { case face, noFace, tooSmall }

    static func check(photo path: String) async -> Result {
        guard let cg = await uprightImage(path) else { return .noFace }
        guard let biggest = await faces(in: cg).map({ $0.width * $0.height }).max() else { return .noFace }
        // At least ~2% of the frame: a face you could actually recognise.
        return biggest >= 0.02 ? .face : .tooSmall
    }

    /// The photo at 1024 px at most, upright, decoded off the main thread (a picked file with ImageIO).
    private static func uprightImage(_ path: String) async -> CGImage? {
        guard path.hasPrefix("/") else { return UIImage(named: path)?.cgImage }
        return await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                       [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
            return CGImageSourceCreateThumbnailAtIndex(src, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024
            ] as CFDictionary)
        }.value
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

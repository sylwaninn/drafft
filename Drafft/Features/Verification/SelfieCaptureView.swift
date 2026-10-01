@preconcurrency import AVFoundation
import Supabase
import SwiftUI
import Vision

/// The selfie the drafft team asked for (hold `selfie`): the front camera, live, with Apple Vision
/// checking every few frames that one face fills the oval. The shutter only works once it does, and the
/// photo taken is checked again before it can be sent. Sending moves the account to review.
struct SelfieCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var model = SelfieCaptureModel()

    var body: some View {
        VStack(spacing: DS.Space.lg) {
            HStack {
                Button { dismiss() } label: {
                    Image("close")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.14), in: .circle)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("Close")
                Spacer()
            }
            viewfinder
            hint
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.top, DS.Space.sm)
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        .nightSurface()
        .background(DS.Palette.night.ignoresSafeArea())
        .task { await model.start() }
        .onDisappear { model.stop() }
        .onChange(of: model.sent) { _, sent in if sent { dismiss() } }
    }

    /// The camera, or the photo taken, in a 3:4 frame with the oval to put the face in. The frame's size
    /// comes from the space, never from the photo (a filled photo would widen the whole screen).
    private var viewfinder: some View {
        Color.clear
            .aspectRatio(3 / 4, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                switch model.stage {
                case let .captured(image), let .sending(image):
                    Image(uiImage: image).resizable().scaledToFill()
                case .live:
                    CameraPreview(session: model.camera.session)
                default:
                    DS.Palette.nightRaised
                }
            }
            .overlay {
                if model.stage == .live {
                    Ellipse()
                        .strokeBorder(model.framing == .ready ? DS.Palette.positive : .white.opacity(0.55),
                                      style: StrokeStyle(lineWidth: 3, dash: model.framing == .ready ? [] : [8, 8]))
                        .padding(.horizontal, 44)
                        .padding(.vertical, 56)
                        .animation(Motion.select, value: model.framing == .ready)
                        .accessibilityHidden(true)
                }
            }
            .clipShape(.rect(cornerRadius: DS.Radius.xl))
    }

    /// What to do now, in one raised block under the frame.
    private var hint: some View {
        HStack(spacing: DS.Space.md) {
            Image(model.isCaptured ? "sun" : "face-scan-square")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.1), in: .circle)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            Text(branded: model.hint, font: .subheadline.weight(.semibold))
                .foregroundStyle(model.error == nil ? .white : DS.Palette.negative)
                .fixedSize(horizontal: false, vertical: true)
                .rollingDigits(wording: model.hint)
            Spacer(minLength: 0)
        }
        .padding(DS.Space.md)
        .background(DS.Palette.nightRaised, in: .rect(cornerRadius: DS.Radius.xl))
        .animation(Motion.select, value: model.hint)
        .accessibilityElement(children: .combine)
    }

    /// Pinned: the shutter (live), send or retake (taken), or the way to Settings (no camera access).
    private var actions: some View {
        VStack(spacing: DS.Space.xs) {
            switch model.stage {
            case .captured, .sending:
                Button { Task { await model.send() } } label: {
                    if model.isSending {
                        ProgressView().tint(DS.Palette.onAccentOnNight)
                    } else {
                        Label("Send my selfie", image: "plain")
                    }
                }
                .buttonStyle(.drafftPrimary)
                .disabled(model.isSending)
                Button("Retake") { Task { await model.retake() } }
                    .buttonStyle(.textLink(fullWidth: true))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .disabled(model.isSending)
            case .denied:
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Label("Open Settings", image: "settings")
                }
                .buttonStyle(.drafftPrimary)
            default:
                Button { Task { await model.shoot() } } label: { Label("Take the selfie", image: "camera") }
                    .buttonStyle(.drafftPrimary)
                    .disabled(model.stage != .live || model.framing != .ready || model.shooting)
            }
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.top, DS.Space.sm)
        .padding(.bottom, DS.Space.xs)
        .background(DS.Palette.night)
    }
}

// MARK: - Framing

/// What the live check sees. Vision boxes are in 0...1 of the upright frame.
enum SelfieFraming: Equatable {
    case noFace, severalFaces, tooFar, offCenter, ready

    static func evaluate(_ faces: [CGRect]) -> SelfieFraming {
        // Faces far in the background don't count as someone else in the picture.
        let near = faces.filter { $0.width >= 0.12 }
        if near.count > 1 { return .severalFaces }
        guard let face = near.first else { return faces.isEmpty ? .noFace : .tooFar }
        if face.width < 0.3 { return .tooFar }
        if abs(face.midX - 0.5) > 0.18 || abs(face.midY - 0.5) > 0.22 { return .offCenter }
        return .ready
    }

    var hint: String {
        switch self {
        case .noFace: L("Place your face in the oval.")
        case .severalFaces: L("Just you in the frame.")
        case .tooFar: L("Come a little closer.")
        case .offCenter: L("Center your face in the oval.")
        case .ready: L("Perfect. Hold still and take it.")
        }
    }
}

// MARK: - Model

@MainActor
@Observable
final class SelfieCaptureModel {
    enum Stage: Equatable {
        case starting, live, unavailable, denied
        case captured(UIImage)
        case sending(UIImage)
    }

    private(set) var stage: Stage = .starting
    private(set) var framing: SelfieFraming = .noFace
    private(set) var error: String?
    private(set) var shooting = false
    /// Set once the selfie is sent: the view closes, the hold screen turns to review.
    private(set) var sent = false
    /// Made when first used: the view's `@State` default is rebuilt each time its parent re-renders,
    /// and a capture session isn't free.
    @ObservationIgnored lazy var camera = SelfieCamera()

    var isCaptured: Bool { if case .captured = stage { true } else { false } }
    var isSending: Bool { if case .sending = stage { true } else { false } }

    var hint: String {
        if let error { return error }
        switch stage {
        case .starting: return L("Opening the camera.")
        case .unavailable: return L("The camera isn't available on this device.")
        case .denied: return L("drafft needs the camera for your selfie. Allow it in Settings.")
        case .captured, .sending: return L("Is your face clear and well lit?")
        case .live: return framing.hint
        }
    }

    func start() async {
        error = nil
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { stage = .denied; return }
        case .authorized: break
        default: stage = .denied; return
        }
        camera.onFraming = { [weak self] framing in
            guard let self else { return }
            // A failed shot's message stays until the person moves.
            if framing != self.framing { error = nil }
            self.framing = framing
        }
        stage = await camera.start() ? .live : .unavailable
    }

    func stop() { camera.stop() }

    /// Takes the photo, then checks it again: what's sent must show the face as the live check saw it.
    func shoot() async {
        guard stage == .live, framing == .ready, !shooting else { return }
        shooting = true
        defer { shooting = false }
        Haptics.tap()
        // One face, big enough: the still may sit a little off the centre the live check wanted.
        guard let image = await camera.capture(), let cg = image.cgImage,
              [.ready, .offCenter].contains(SelfieFraming.evaluate(await FaceCheck.faces(in: cg, orientation: image.cgOrientation)))
        else {
            error = L("We couldn't see your face clearly. Try again.")
            Haptics.warning()
            return
        }
        error = nil
        camera.stop()
        withAnimation(Motion.snappy) { stage = .captured(image) }
    }

    func retake() async {
        withAnimation(Motion.snappy) { stage = .starting }
        await start()
    }

    func send() async {
        guard case let .captured(image) = stage else { return }
        stage = .sending(image)
        error = nil
        do {
            try await SelfieUpload.send(image)
            Haptics.success()
            // The hold turns to review first: the camera closes onto the review screen, never back onto
            // the selfie request.
            await AccountModeration.shared.load()
            sent = true
        } catch where ServerMessage.code(of: error) == "not_requested" {
            // The team decided meanwhile (the hold was lifted or changed): nothing left to send here.
            await AccountModeration.shared.load()
            sent = true
        } catch {
            self.error = error is URLError ? L("Couldn't connect. Check your connection and try again.")
                : L("Your selfie couldn't be sent. Try again.")
            Haptics.warning()
            stage = .captured(image)
        }
    }
}

private extension UIImage {
    var cgOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        default: .up
        }
    }
}

// MARK: - Upload

/// Into the private bucket (only the drafft team reads it), then `submit_selfie`: the account goes to
/// review. Resized to 1,600 px: enough to compare with the photos, not a full-size portrait.
enum SelfieUpload {
    struct Failed: Error {}

    static func send(_ image: UIImage) async throws {
        guard let id = await Backend.shared.userID, let data = image.resized(maxSide: 1600).jpegData(compressionQuality: 0.82)
        else { throw Failed() }
        let path = "\(id.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        _ = try await Backend.shared.client.storage.from("verification-selfies")
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
        _ = try await Backend.shared.rpc("submit_selfie", ["p_path": path])
    }
}

private extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(size.width, size.height))
        guard scale < 1 else { return self }
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}

// MARK: - Camera

/// The front camera: frames for the live face check, and one photo when asked. Runs on its own queue.
final class SelfieCamera: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "so.drafft.selfie-camera")
    private let video = AVCaptureVideoDataOutput()
    private let photo = AVCapturePhotoOutput()
    private var configured = false
    private var frame = 0
    private var photoTaken: CheckedContinuation<UIImage?, Never>?
    /// Apple's angle for an upright photo, whatever way the phone is held.
    private var rotation: AVCaptureDevice.RotationCoordinator?
    /// Each new framing, on the main actor.
    @MainActor var onFraming: ((SelfieFraming) -> Void)?

    /// False when there's no front camera (the Simulator).
    func start() async -> Bool {
        await withCheckedContinuation { done in
            queue.async { [self] in
                if !configured {
                    guard configure() else { done.resume(returning: false); return }
                    configured = true
                }
                if !session.isRunning { session.startRunning() }
                done.resume(returning: true)
            }
        }
    }

    func stop() {
        queue.async { [self] in if session.isRunning { session.stopRunning() } }
    }

    func capture() async -> UIImage? {
        await withCheckedContinuation { done in
            queue.async { [self] in
                guard session.isRunning else { done.resume(returning: nil); return }
                photoTaken = done
                if let connection = photo.connection(with: .video), let angle = rotation?.videoRotationAngleForHorizonLevelCapture,
                   connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
                photo.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    private func configure() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(video), session.canAddOutput(photo) else { return false }
        session.addInput(input)
        rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        video.alwaysDiscardsLateVideoFrames = true
        video.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(video)
        session.addOutput(photo)
        // Upright and mirrored, as the person sees themselves: Vision reads the frames as they are.
        for connection in [video.connection(with: .video), photo.connection(with: .video)].compactMap({ $0 }) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
        return true
    }
}

extension SelfieCamera: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Every 4th frame (about 7 checks a second) is plenty, and keeps the phone cool.
        frame += 1
        guard frame.isMultiple(of: 4), let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up).perform([request])
        let framing = SelfieFraming.evaluate((request.results ?? []).map(\.boundingBox))
        Task { @MainActor [weak self] in self?.onFraming?(framing) }
    }
}

extension SelfieCamera: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:)).map(Self.upright)
        queue.async { [self] in
            photoTaken?.resume(returning: image)
            photoTaken = nil
        }
    }
}

extension SelfieCamera {
    /// The photo with its pixels upright, as the person saw themselves (mirrored), whatever orientation
    /// flag the camera wrote: shown, checked and uploaded the same way. The app is portrait only, so a
    /// photo still wider than tall was taken sideways: it's turned a quarter, the way that shows the face
    /// upright (Vision finds faces standing up).
    static func upright(_ image: UIImage) -> UIImage {
        let baked = image.redrawn()
        guard baked.size.width > baked.size.height, let cg = baked.cgImage else { return baked }
        let turns = [UIImage.Orientation.right, .left].map { UIImage(cgImage: cg, scale: 1, orientation: $0).redrawn() }
        return turns.first(where: hasFace) ?? turns[0]
    }

    private static func hasFace(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        let request = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cgImage: cg, orientation: .up).perform([request])
        return !(request.results ?? []).isEmpty
    }
}

private extension UIImage {
    /// Drawn again with `.up` orientation: what's on screen is what's in the pixels.
    func redrawn() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}

/// The live camera, filling its frame.
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer } // swiftlint:disable:this force_cast
    }
}

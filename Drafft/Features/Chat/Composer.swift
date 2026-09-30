import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

/// Text + attachments + hold-to-record voice. Everything sends optimistically.
struct Composer: View {
    @Binding var text: String
    let onSend: (MessageContent) -> Void
    /// The message being replied to, shown above the field ("Replying to Sam").
    var reply: (id: String, author: String, text: String)?
    var onCancelReply: () -> Void = {}

    @State private var recorder = VoiceRecorder()
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showPhotos = false
    @State private var showCamera = false
    @State private var dragX: CGFloat = 0
    /// Upward drag while recording (negative), toward the lock.
    @State private var dragY: CGFloat = 0
    @State private var locked = false
    @State private var holdHint = false
    @State private var pressStart: Date?
    /// True while a finger is on the mic. Resets on its own when the system cancels the touch
    /// (a sheet, a call, the app going away), which never calls onEnded: see `releaseMic`.
    @GestureState private var micHeld = false
    @State private var hintTask: Task<Void, Never>?
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cancelThreshold: CGFloat = -110
    private let lockThreshold: CGFloat = -90

    /// Touch-down on the mic, microphone still opening: the recording UI already shows.
    @State private var starting = false
    /// The recording UI: from the instant the finger lands, not once the microphone is open (the
    /// audio session takes a moment, and waiting for it felt like a required hold).
    private var isRecording: Bool { recorder.state == .recording || starting }
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: DS.Space.xs) {
            if holdHint {
                Text("Hold to record, release to send")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DS.Palette.canvas)
                    .padding(.horizontal, DS.Space.md)
                    .padding(.vertical, 6)
                    .background(DS.Palette.ink, in: .capsule)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            // Glass controls morph into each other as the composer changes state.
            GlassEffectContainer(spacing: DS.Space.sm) {
            HStack(alignment: .bottom, spacing: DS.Space.sm) {
                if !isRecording { attachMenu }
                // The field stays in the hierarchy while recording (hidden under the bar): removing
                // it would drop its focus, and the keyboard with it.
                ZStack(alignment: .bottom) {
                    field
                        .allowsHitTesting(!isRecording)
                        .accessibilityHidden(isRecording)
                    if isRecording { recordingBar }
                }
                trailingButton
            }
            }
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.top, DS.Space.xs)
        .padding(.bottom, DS.Space.xs)
        .animation(Motion.snappy, value: reply?.id)
        .onChange(of: reply?.id) { _, id in if id != nil { focused = true } }
        .animation(Motion.snappy, value: isRecording)
        .animation(Motion.snappy, value: trimmed.isEmpty)
        .animation(Motion.snappy, value: holdHint)
        .onAppear { VoiceRecorder.prewarm() }
        .photosPicker(isPresented: $showPhotos, selection: $pickerItems, maxSelectionCount: 5, matching: .any(of: [.images, .videos]))
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            pickerItems = []
            Task { await sendPicked(items) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { capture in
                Task {
                    switch capture {
                    case .photo(let image):
                        if let data = image.jpegData(compressionQuality: 0.85) {
                            onSend(.photo(asset: nil, imageData: data))
                        }
                    case .video(let url):
                        await sendVideo(url)
                    }
                }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Pieces

    /// Photos and videos: take one now with the camera, or pick up to five from the library.
    private var attachMenu: some View {
        Menu {
            if CameraPicker.isAvailable {
                Button("Take a photo or video", image: .icon("camera")) { showCamera = true }
            }
            Button("Choose from library", image: .icon("gallery")) { showPhotos = true }
        } label: {
            Image("add")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(DS.Palette.ink)
                .frame(width: 44, height: 44)
                .glassEffect(.regular, in: .circle)
                // Glass isn't hit-testable: without this only the glyph answered.
                .contentShape(.circle)
        }
        .accessibilityLabel("Send a photo or video")
        .transition(.scale.combined(with: .opacity))
    }

    /// The message field. When replying, the quote sits inside the same glass shape, above the
    /// text, like iMessage: one object, not a banner floating over the composer.
    private var field: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let reply {
                HStack(alignment: .top, spacing: DS.Space.sm) {
                    Capsule().fill(DS.Palette.lime).frame(width: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(reply.author == "yourself" ? "Replying to yourself" : "Replying to \(reply.author)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(DS.Palette.accentInk)
                        Text(reply.text)
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.body)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button(action: onCancelReply) {
                        Image("close-circle")
                            .font(.body)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(DS.Palette.mute)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    // 44 pt to hit, laid out as 32 so the quote doesn't grow.
                    .padding(-6)
                    .accessibilityLabel("Cancel reply")
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, DS.Space.md)
                .padding(.trailing, DS.Space.xs)
                .padding(.top, DS.Space.sm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            TextField("Message", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .font(.body)
                .padding(.horizontal, DS.Space.lg)
                .padding(.vertical, 11)
                .frame(minHeight: 44)
                // Multi-line: Return adds a line (its key stays "return", not a send arrow).
        }
        // Anywhere on the glass field (reply quote included) puts the cursor in it.
        .contentShape(.rect(cornerRadius: 22))
        .onTapGesture { focused = true }
        // While recording, text and glass both go (opacity alone leaves the glass drawn by the
        // container, and the text shows through the recording bar). Quick fade, then scale.
        .opacity(isRecording ? 0 : 1)
        .scaleEffect(isRecording ? 0.96 : 1, anchor: .trailing)
        // Plain glass, not .interactive(): interactive glass runs its own touch handling and
        // could hold back the first taps on the field.
        .glassEffect(isRecording ? .identity : .regular, in: .rect(cornerRadius: 22))
        .animation(.easeOut(duration: 0.12), value: isRecording)
    }

    @ViewBuilder
    private var trailingButton: some View {
        if !trimmed.isEmpty && !isRecording {
            Button(action: sendText) {
                Image("arrow-up")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(DS.Palette.onLime)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.tint(DS.Palette.lime), in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Send")
            .transition(.scale.combined(with: .opacity))
        } else if isRecording && locked {
            Button {
                finishRecording(cancel: false)
            } label: {
                Image("arrow-up")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(DS.Palette.onLime)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.tint(DS.Palette.lime), in: .circle)
                    .contentShape(.circle)
            }
            .accessibilityLabel("Send voice message")
        } else {
            micButton
        }
    }

    /// 0 at rest, 1 when the mic reaches the lock.
    private var lockProgress: CGFloat { min(1, max(0, dragY / lockThreshold)) }

    /// Hold to record. While holding, a glass rail with a lock rises above the mic: drag up and
    /// the mic travels into it, the rail shortens and the padlock closes; slide left to cancel.
    private var micButton: some View {
        let p = lockProgress
        return ZStack {
            if isRecording && !locked {
                lockRail(p)
                    .offset(y: -104)
                    .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
            }
            Image("microphone")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(isRecording ? DS.Palette.onLime : DS.Palette.ink)
                .frame(width: 44, height: 44)
                // Not .interactive(): interactive glass handles touches itself and swallowed the hold.
                .glassEffect(isRecording ? .regular.tint(DS.Palette.lime) : .regular, in: .circle)
                .scaleEffect(isRecording ? 1.5 - 0.35 * p : 1)
                .offset(x: isRecording ? max(dragX, cancelThreshold) * 0.25 : 0,
                        y: isRecording ? max(dragY, lockThreshold) : 0)
        }
        .frame(width: 44, height: 44)
        .contentShape(.circle)
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.8), value: dragY)
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .updating($micHeld) { _, held, _ in held = true }
                .onChanged { v in
                    if pressStart == nil {
                        let start = Date.now
                        pressStart = start
                        locked = false
                        dragX = 0
                        dragY = 0
                        starting = true
                        Haptics.tap() // felt on touch-down, before recording starts
                        Task { await beginRecording(heldSince: start) }
                    }
                    guard isRecording, !locked else { return }
                    // One axis at a time: up toward the lock, or left toward cancel.
                    if -v.translation.height > abs(v.translation.width) {
                        dragX = 0
                        let wasBelow = dragY > lockThreshold
                        dragY = min(0, v.translation.height)
                        if wasBelow && dragY <= lockThreshold {
                            Haptics.thump()
                            withAnimation(Motion.bouncy) { locked = true; dragX = 0; dragY = 0 }
                        }
                    } else {
                        dragY = 0
                        dragX = min(0, v.translation.width)
                        if dragX < cancelThreshold { finishRecording(cancel: true) }
                    }
                }
                .onEnded { _ in releaseMic() }
        )
        // A cancelled touch still ends the press, so the mic never stays "held" and ignores
        // the next hold.
        .onChange(of: micHeld) { _, held in if !held { releaseMic() } }
        .accessibilityLabel("Record voice message")
        .accessibilityHint("Hold to record, release to send. Slide left to cancel, up to lock.")
        .accessibilityAction(named: "Start recording") {
            Task { if await recorder.start() { locked = true } }
        }
    }

    /// Glass rail above the mic: open padlock on top, a chevron nudging upward. It shortens as the
    /// mic climbs and the padlock closes at the top.
    private func lockRail(_ p: CGFloat) -> some View {
        VStack(spacing: 8) {
            Image(p >= 1 ? "lock-keyhole-minimalistic" : "lock-keyhole-minimalistic-unlocked")
                .font(.system(size: 15, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
            Image("alt-arrow-up")
                .font(.system(size: 11, weight: .heavy))
                .symbolEffect(.bounce.up, options: .repeating, isActive: !reduceMotion)
                .opacity(Double(1 - p))
        }
        .foregroundStyle(DS.Palette.ink)
        .padding(.vertical, 12)
        .frame(width: 40, height: 84 - 28 * p, alignment: .top)
        .glassEffect(.regular, in: .capsule)
        .offset(y: 14 * p)
        .accessibilityHidden(true)
    }

    private var recordingBar: some View {
        HStack(spacing: DS.Space.md) {
            if locked {
                Button {
                    finishRecording(cancel: true)
                } label: {
                    Image("trash-bin-minimalistic")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DS.Palette.negative)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Discard recording")
            } else {
                Circle().fill(DS.Palette.negative).frame(width: 10, height: 10)
                    .padding(.leading, DS.Space.md)
                    .accessibilityHidden(true)
            }
            Text(recorder.duration.clock)
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(DS.Palette.ink)
                .contentTransition(.numericText())
            LiveWave(levels: recorder.levels)
                .frame(height: 28)
            if !locked {
                Label("Slide to cancel", image: "alt-arrow-left")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DS.Palette.body)
                    .opacity(1 - Double(min(1, abs(dragX) / abs(cancelThreshold))))
                    .fixedSize()
            }
        }
        .frame(minHeight: 44)
        .padding(.trailing, DS.Space.md)
        .glassEffect(.regular, in: .capsule)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    // MARK: Actions

    private func sendText() {
        guard !trimmed.isEmpty else { return }
        onSend(.text(trimmed))
        text = ""
    }

    /// Recording starts on touch-down, as in WhatsApp: the audio session spins up while the
    /// finger is still landing. A tap shorter than 0.1 s is discarded and shows the hint instead.
    private func beginRecording(heldSince start: Date) async {
        guard pressStart == start else { starting = false; return } // released (or pressed again) meanwhile
        let ok = await recorder.start()
        starting = false
        guard ok else { return }
        // Released or cancelled while the recorder was starting: don't leave it recording on its own.
        guard pressStart == start || locked else {
            _ = recorder.finish(cancel: true)
            return
        }
        Haptics.thump() // the microphone is live
    }

    /// End of a press on the mic, released or cancelled. Runs once (the second call finds no press).
    private func releaseMic() {
        guard let start = pressStart else { return }
        let held = Date.now.timeIntervalSince(start)
        pressStart = nil
        if held < 0.1 {
            starting = false
            if recorder.state == .recording { _ = recorder.finish(cancel: true) }
            flashHint()
            return
        }
        // Released before the microphone finished opening: nothing was recorded.
        if starting && !locked {
            starting = false
            return
        }
        if isRecording && !locked { finishRecording(cancel: false) }
    }

    private func finishRecording(cancel: Bool) {
        let r = recorder.finish(cancel: cancel)
        starting = false
        // Once locked, the mic gave way to Send mid-press, so that press never got its end:
        // clear it, or the next hold on the mic would be ignored. A cancel ends the press too (and
        // stops a microphone still opening from recording on its own).
        if locked || cancel { pressStart = nil }
        withAnimation(Motion.snappy) { locked = false; dragX = 0; dragY = 0 }
        if cancel {
            Haptics.warning()
        } else if let r {
            onSend(.voice(url: r.url, duration: r.duration, levels: r.levels))
        }
    }

    private func flashHint() {
        Haptics.warning()
        holdHint = true
        // A new tap restarts the timer instead of an older one hiding the hint early.
        hintTask?.cancel()
        hintTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            holdHint = false
        }
    }

    private func sendPicked(_ items: [PhotosPickerItem]) async {
        for item in items {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }),
               let movie = try? await item.loadTransferable(type: PickedMovie.self) {
                await sendVideo(movie.url)
            } else if let data = try? await item.loadTransferable(type: Data.self) {
                // At most 2048 px, decoded off the main thread: the thread never holds a 48 MP original.
                let photo = (try? await PhotoCompressor.prepare(data))?.data ?? data
                onSend(.photo(asset: nil, imageData: photo))
            }
        }
    }

    /// A video bubble: its first frame as the poster, and its length.
    private func sendVideo(_ url: URL) async {
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 600, height: 600)
        var thumb: Data?
        if let cg = try? await gen.image(at: .zero).image {
            thumb = UIImage(cgImage: cg).jpegData(compressionQuality: 0.8)
        }
        onSend(.video(url: url, thumbnail: thumb, duration: duration))
    }
}

struct LiveWave: View {
    let levels: [Float]
    var body: some View {
        GeometryReader { geo in
            let maxBars = Int(geo.size.width / 5)
            let recent = Array(levels.suffix(maxBars))
            HStack(spacing: 2) {
                Spacer(minLength: 0)
                ForEach(Array(recent.enumerated()), id: \.offset) { _, l in
                    Capsule()
                        .fill(DS.Palette.ink)
                        .frame(width: 3, height: max(3, geo.size.height * CGFloat(l)))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

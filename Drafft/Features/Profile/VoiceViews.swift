import SwiftUI

/// Waveform bars with a played portion; tap or drag to seek when it's the active clip.
struct WaveformBars: View {
    let levels: [Float]
    var progress: Double
    var played: Color
    var unplayed: Color
    var barWidth: CGFloat = 3
    /// Drag to scrub. Off in chat bubbles, where a sideways drag means "reply".
    var scrubs = true
    var onSeek: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geo in
            // One Canvas instead of two stacks of bars and a mask: a chat with several voice
            // messages lays out fast, and playback redraws one layer per frame.
            Canvas { ctx, size in
                // Always span the full width: bars keep their width (shrinking if needed), and the
                // gaps stretch so the last bar lands on the right edge. When space is tight, show
                // fewer bars (downsampled) rather than overflowing the frame.
                let minGap: CGFloat = 1.5, minBar: CGFloat = 2
                let fit = max(1, Int((size.width + minGap) / (minBar + minGap)))
                let shown = levels.count > fit ? VoiceRecorder.downsample(levels, to: fit) : levels
                let count = max(shown.count, 1)
                let bar = max(minBar, min(barWidth, (size.width - minGap * CGFloat(count - 1)) / CGFloat(count)))
                let spacing = count > 1 ? max(minGap, (size.width - bar * CGFloat(count)) / CGFloat(count - 1)) : 0
                var bars = Path()
                for (i, level) in shown.enumerated() {
                    let h = max(bar, size.height * CGFloat(level))
                    let rect = CGRect(x: CGFloat(i) * (bar + spacing), y: (size.height - h) / 2, width: bar, height: h)
                    bars.addRoundedRect(in: rect, cornerSize: CGSize(width: bar / 2, height: bar / 2))
                }
                ctx.fill(bars, with: .color(unplayed))
                // Played part: the same bars in the played colour, clipped to the progress, so it
                // glides instead of jumping bar by bar.
                let p = CGFloat(min(max(progress, 0), 1))
                if p > 0 {
                    var played = ctx
                    played.clip(to: Path(CGRect(x: 0, y: 0, width: size.width * p, height: size.height)))
                    played.fill(bars, with: .color(self.played))
                }
            }
            .contentShape(.rect)
            // Tap to seek, or drag sideways. Simultaneous, and horizontal-only, so a vertical
            // swipe that starts on the waveform still scrolls the page.
            .onTapGesture { loc in onSeek?(min(1, max(0, loc.x / geo.size.width))) }
            .simultaneousGesture(
                DragGesture(minimumDistance: 6).onChanged { v in
                    guard abs(v.translation.width) > abs(v.translation.height) else { return }
                    onSeek?(min(1, max(0, v.location.x / geo.size.width)))
                }, including: onSeek == nil || !scrubs ? .none : .all
            )
        }
        .accessibilityHidden(true)
    }
}

/// Voice clip player used on profiles and in chat.
struct VoicePlayer: View {
    let url: URL?
    let duration: TimeInterval
    let levels: [Float]
    var tint: Color = DS.Palette.ink
    var track: Color = DS.Palette.ink.opacity(0.22)
    var buttonFill: Color = DS.Palette.lime
    var buttonGlyph: Color = DS.Palette.onLime
    var showsSpeed = false
    /// Drag on the waveform to scrub (tap to seek always works).
    var scrubbable = true

    @State private var audio = AudioPlayback.shared

    private var isCurrent: Bool { audio.isCurrent(url) }
    private var playing: Bool { isCurrent && audio.isPlaying }

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Button {
                guard let url else { return }
                Haptics.tap()
                audio.toggle(url)
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(buttonGlyph)
                    .frame(width: 44, height: 44)
                    .background(buttonFill, in: .circle)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel(playing ? "Pause voice message" : "Play voice message, \(Int(duration)) seconds")

            TimelineView(.animation(paused: !playing)) { _ in
                WaveformBars(levels: levels, progress: isCurrent ? audio.liveProgress : 0, played: tint, unplayed: track,
                             scrubs: scrubbable) { f in
                    if isCurrent { audio.seek(to: f) }
                }
            }
            .frame(height: 32)
            .layoutPriority(-1)

            Text((isCurrent && audio.elapsed > 0 ? audio.elapsed : duration).clock)
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
                .frame(minWidth: 34, alignment: .trailing)
                .fixedSize()
                .contentTransition(.numericText())

            if showsSpeed && isCurrent {
                Button {
                    audio.rate = audio.rate == 1 ? 1.5 : (audio.rate == 1.5 ? 2 : 1)
                    Haptics.select()
                } label: {
                    Text(audio.rate == 1 ? "1×" : (audio.rate == 1.5 ? "1.5×" : "2×"))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 8)
                        .frame(minHeight: 28)
                        .background(tint.opacity(0.12), in: .capsule)
                        .foregroundStyle(tint)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Playback speed")
                .accessibilityValue(audio.rate == 1 ? "Normal" : (audio.rate == 1.5 ? "1.5 times" : "2 times"))
            }
        }
        .animation(Motion.snappy, value: isCurrent)
    }
}

/// Voice intro recorder (sign-up and Edit profile). Idle and recording share one layout: a
/// 15-second track that fills with the live waveform, the time, and one round button. Once
/// recorded: listen, record again (starts a new take right away) or delete.
struct VoiceIntroRecorder: View {
    @Binding var result: (url: URL, duration: TimeInterval, levels: [Float])?
    /// False when placed inside an existing block, so it doesn't draw a card within a card.
    var framed = true
    @State private var recorder = VoiceRecorder()
    private let limit: TimeInterval = 15

    private var recording: Bool { recorder.state == .recording }

    /// Quiet recordings produce flat bars; stretch them so the waveform always reads.
    private func normalized(_ levels: [Float]) -> [Float] {
        let peak = levels.max() ?? 1
        guard peak > 0.01 else { return levels }
        return levels.map { max(0.12, min(1, $0 / peak)) }
    }

    var body: some View {
        Group {
            if let result, !recording {
                recorded(result)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                capture
                    .transition(.opacity)
            }
        }
        .padding(framed ? DS.Space.xl : 0)
        .frame(maxWidth: .infinity)
        .background(framed ? AnyShapeStyle(DS.Palette.canvas) : AnyShapeStyle(.clear), in: .rect(cornerRadius: DS.Radius.xl))
        .animation(Motion.snappy, value: recording)
        .onChange(of: recorder.duration) { _, d in
            if d >= limit { stop() }
        }
    }

    // MARK: Idle and recording

    private var capture: some View {
        VStack(spacing: DS.Space.lg) {
            VStack(spacing: DS.Space.sm) {
                RecordingTrack(levels: recorder.levels, elapsed: recorder.duration, limit: limit,
                               active: recording)
                    .frame(height: 56)
                HStack {
                    HStack(spacing: 6) {
                        if recording {
                            Circle().fill(DS.Palette.negative).frame(width: 8, height: 8)
                                .transition(.scale.combined(with: .opacity))
                        }
                        Text(recorder.duration.clock)
                            .contentTransition(.numericText())
                    }
                    .foregroundStyle(recording ? DS.Palette.ink : DS.Palette.body)
                    Spacer()
                    Text(limit.clock).foregroundStyle(DS.Palette.body)
                }
                .font(.footnote.weight(.semibold).monospacedDigit())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(recording ? "Recording, \(Int(recorder.duration)) of 15 seconds" : "Up to 15 seconds")
            }

            Button {
                Task { await toggle() }
            } label: {
                Image(systemName: recording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 26, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(recording ? DS.Palette.lime : DS.Palette.onLime)
                    .frame(width: 76, height: 76)
                    .background(recording ? DS.Palette.night : DS.Palette.lime, in: .circle)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel(recording ? "Stop recording" : "Record voice intro")

            Group {
                if recorder.state == .denied {
                    Text(branded: L("Microphone access is off. Turn it on in Settings › drafft to record."),
                         font: .footnote.weight(.semibold), brandWeight: .heavy)
                        .foregroundStyle(DS.Palette.negative)
                } else {
                    Text(recording ? "Tap to stop" : "Tap to record")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Palette.body)
                        .contentTransition(.opacity)
                }
            }
            .multilineTextAlignment(.center)
        }
        .padding(.vertical, framed ? 0 : DS.Space.sm)
    }

    // MARK: Recorded

    private func recorded(_ result: (url: URL, duration: TimeInterval, levels: [Float])) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            VoicePlayer(url: result.url, duration: result.duration, levels: normalized(result.levels))
                .padding(DS.Space.md)
                .background(DS.Palette.canvasSoft, in: .rect(cornerRadius: DS.Radius.lg))
            HStack(spacing: DS.Space.sm) {
                Button {
                    Task { await recordAgain() }
                } label: {
                    Label("Record again", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(DrafftButtonStyle(kind: .secondary))
                Button(role: .destructive) {
                    Haptics.tap()
                    discard()
                } label: {
                    Image(systemName: "trash")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DS.Palette.negative)
                        .frame(width: 52, height: 52)
                        .background(DS.Palette.canvasSoft, in: .circle)
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("Delete recording")
            }
        }
    }

    // MARK: Actions

    private func toggle() async {
        if recording { stop() } else {
            Haptics.thump()
            _ = await recorder.start()
        }
    }

    /// A new take starts straight away (otherwise it would do the same as delete).
    private func recordAgain() async {
        Haptics.thump()
        AudioPlayback.shared.stop()
        let previous = result
        if await recorder.start() {
            if let url = previous?.url { try? FileManager.default.removeItem(at: url) }
            withAnimation(Motion.snappy) { result = nil }
        }
    }

    private func discard() {
        AudioPlayback.shared.stop()
        if let url = result?.url { try? FileManager.default.removeItem(at: url) }
        withAnimation(Motion.snappy) { result = nil }
    }

    private func stop() {
        Haptics.success()
        if let r = recorder.finish() {
            withAnimation(Motion.snappy) { result = r }
        }
    }
}

/// The 15-second track: one slot per bar across the width. Recorded slots show the live level
/// in ink; the rest are small dots showing the time left.
struct RecordingTrack: View {
    let levels: [Float]
    let elapsed: TimeInterval
    let limit: TimeInterval
    var active: Bool
    /// Seconds between two level samples (VoiceRecorder samples every 0.08 s).
    private let sampleEvery: TimeInterval = 0.08

    var body: some View {
        GeometryReader { geo in
            let bar: CGFloat = 3, gap: CGFloat = 3
            let slots = max(1, Int((geo.size.width + gap) / (bar + gap)))
            let perSlot = limit / sampleEvery / Double(slots)
            let filled = min(slots, Int((elapsed / limit) * Double(slots)))
            HStack(alignment: .center, spacing: gap) {
                ForEach(0..<slots, id: \.self) { i in
                    let level = i < filled ? Self.level(levels, from: Int(Double(i) * perSlot), to: Int(Double(i + 1) * perSlot)) : 0
                    Capsule()
                        .fill(i < filled ? DS.Palette.ink : DS.Palette.ink.opacity(active ? 0.18 : 0.14))
                        .frame(width: bar, height: i < filled ? max(bar * 2, geo.size.height * CGFloat(level)) : bar)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.linear(duration: 0.08), value: filled)
        }
        .accessibilityHidden(true)
    }

    private static func level(_ values: [Float], from a: Int, to b: Int) -> Float {
        guard a < values.count else { return 0.12 }
        let slice = values[a..<min(values.count, max(a + 1, b))]
        // Quiet voices still read.
        return max(0.12, min(1, (slice.max() ?? 0) * 1.6))
    }
}

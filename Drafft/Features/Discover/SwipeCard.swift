import Nuke
import SwiftUI

struct SwipeCard: View {
    let profile: Profile
    let me: Profile
    /// -1 (pass) … 1 (like), drives the stamps.
    let progress: CGFloat
    let isTop: Bool
    /// Download order of its photo: the card in play first, then the ones behind it.
    var photoPriority: ImageRequest.Priority = .normal
    let onOpen: () -> Void

    @State private var audio = AudioPlayback.shared

    private var voiceURL: URL? { profile.voiceIntro.flatMap(AudioPlayback.url(for:)) }

    var body: some View {
        ZStack(alignment: .bottom) {
            Photo(name: profile.portrait, priority: photoPriority)

            // Scrims so the identity (top) and sports (bottom) stay readable on any photo.
            // design-lint: allow gradient - photo scrims for the identity and sports
            LinearGradient(stops: [
                .init(color: DS.Palette.night.opacity(0.72), location: 0),
                .init(color: .clear, location: 0.3),
                .init(color: .clear, location: 0.62),
                .init(color: DS.Palette.night.opacity(0.85), location: 1)
            ], startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)

            // The whole card opens the full profile; photos are browsed there.
            Color.clear
                .contentShape(.rect)
                .onTapGesture(perform: onOpen)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: DS.Space.md) {
                    identity
                    voicePill
                }
                .padding(.leading, DS.Space.xl)
                .padding([.top, .trailing], DS.Space.md)
                Spacer()
            }

            bottomInfo
                .padding(DS.Space.xl)

            stamps
        }
        .nightSurface()
        .clipShape(.rect(cornerRadius: DS.Radius.xl))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(profile.name), \(profile.age). \(profile.sports.map(\.sport.name).joined(separator: ", "))")
    }

    // MARK: Pieces

    @ViewBuilder
    private var voicePill: some View {
        if let url = voiceURL {
            let playing = audio.isCurrent(url) && audio.isPlaying
            Button {
                Haptics.tap()
                if !playing { Telemetry.track(.voiceIntroPlayed(where: ScreenTracker.currentID)) }
                audio.toggle(url)
            } label: {
                HStack(spacing: 6) {
                    Image(playing ? "pause" : "soundwave")
                        .symbolEffect(.variableColor.iterative, isActive: playing)
                        .contentTransition(.symbolEffect(.replace))
                    Text(playing ? audio.elapsed.clock : profile.voiceDuration.clock)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .font(.footnote.weight(.bold))
                .foregroundStyle(playing ? DS.Palette.onAccentOnNight : .white)
                .padding(.horizontal, DS.Space.md)
                .frame(minHeight: 36)
                // Glass over the photo; a dark tint keeps the white legible on bright shots.
                // Accent while playing, so the active state reads at a glance.
                .glassEffect(playing ? .regular.tint(DS.Palette.accentOnNight)
                                     : .regular.tint(.black.opacity(0.3)), in: .capsule)
                .frame(minHeight: 44)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel(playing ? "Pause voice intro" : "Play \(profile.name)'s voice intro")
        }
    }

    private var identity: some View {
        ProfileIdentity(profile: profile, showsSuperLike: true, superLikeActive: isTop)
            .padding(.top, DS.Space.sm)
    }

    private var bottomInfo: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SportChipsPreview(sports: profile.sports.map(\.sport), highlighted: Set(me.sports.map(\.sport)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stamps: some View {
        ZStack {
            stamp("LIKE", color: DS.Palette.like, text: DS.Palette.onLike, angle: -14)
                .opacity(Double(max(0, progress)) * 1.4)
                .scaleEffect(0.8 + max(0, progress) * 0.25)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            stamp("PASS", color: .white, text: DS.Palette.onLike, angle: 14)
                .opacity(Double(max(0, -progress)) * 1.4)
                .scaleEffect(0.8 + max(0, -progress) * 0.25)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(maxHeight: 120)
        .frame(maxHeight: .infinity)
        .padding(.horizontal, DS.Space.xl)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func stamp(_ word: LocalizedStringKey, color: Color, text: Color, angle: Double) -> some View {
        Text(word)
            .font(.display(40))
            .foregroundStyle(text)
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.xs)
            .background(color, in: .rect(cornerRadius: DS.Radius.md))
            .rotationEffect(.degrees(angle))
    }
}

/// Sports only (no levels), capped at two lines; the rest collapses into a "+X" chip.
struct SportChipsPreview: View {
    let sports: [Sport]
    /// Sports shown in lime (the ones you also do).
    var highlighted: Set<Sport> = []
    var maxLines = 2

    var body: some View {
        OverflowFlow(spacing: DS.Space.xs + 2, maxLines: maxLines) {
            ForEach(sports) { SportChip(sport: $0, selected: highlighted.contains($0), onDark: true) }
            // One candidate "+X" badge per possible overflow count; the layout shows the one it needs.
            ForEach(1..<max(sports.count, 1), id: \.self) { hidden in
                Text("+\(hidden)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.Space.md)
                    .padding(.vertical, DS.Space.sm)
                    .background(.white.opacity(0.16), in: .capsule)
                    .layoutValue(key: OverflowBadge.self, value: hidden)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(sports.map { highlighted.contains($0) ? L("\($0.name), you do it too") : $0.name }.joined(separator: ", "))
    }
}

private struct OverflowBadge: LayoutValueKey {
    static let defaultValue: Int? = nil
}

/// Flow layout limited to `maxLines`. Shows as many items as fit, plus the matching "+X" badge.
/// Items and badges that aren't used are parked far outside the bounds (the card clips them).
struct OverflowFlow: Layout {
    var spacing: CGFloat = 8
    var maxLines = 2

    private struct Plan { var frames: [Int: CGRect] = [:]; var size: CGSize = .zero }

    private func plan(width: CGFloat, subviews: Subviews) -> Plan {
        let items = subviews.indices.filter { subviews[$0][OverflowBadge.self] == nil }
        let badges = Dictionary(uniqueKeysWithValues: subviews.indices.compactMap { i in
            subviews[i][OverflowBadge.self].map { ($0, i) }
        })

        func layout(_ indices: [Int]) -> Plan? {
            var p = Plan(), x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, lines = 1
            for i in indices {
                let s = subviews[i].sizeThatFits(.unspecified)
                if x + s.width > width, x > 0 {
                    lines += 1
                    if lines > maxLines { return nil }
                    x = 0; y += rowH + spacing; rowH = 0
                }
                p.frames[i] = CGRect(origin: CGPoint(x: x, y: y), size: s)
                x += s.width + spacing
                rowH = max(rowH, s.height)
                p.size.width = max(p.size.width, x - spacing)
            }
            p.size.height = y + rowH
            return p
        }

        for shown in stride(from: items.count, through: 0, by: -1) {
            var indices = Array(items.prefix(shown))
            let hidden = items.count - shown
            if hidden > 0, let b = badges[hidden] { indices.append(b) }
            if let p = layout(indices) { return p }
        }
        return Plan()
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let p = plan(width: width, subviews: subviews)
        return CGSize(width: proposal.width ?? p.size.width, height: p.size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let p = plan(width: bounds.width, subviews: subviews)
        for i in subviews.indices {
            if let f = p.frames[i] {
                subviews[i].place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(f.size))
            } else {
                subviews[i].place(at: CGPoint(x: -10_000, y: -10_000), proposal: .zero)
            }
        }
    }
}

/// Name, age and area, as shown on the deck card. Reused wherever a profile is shown over its photo.
struct ProfileIdentity: View {
    let profile: Profile
    var nameSize: CGFloat = 34
    var showsLocation = true
    /// Deck only: a red super like disc right after the age when they super liked you.
    var showsSuperLike = false
    /// The super like disc pops in when this turns true (the card reaching the top of the deck).
    var superLikeActive = true

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            NameAgeLine(profile: profile, nameSize: nameSize,
                        nameColor: .white, ageColor: .white.opacity(0.8),
                        showsBadge: showsSuperLike && profile.superLikedMe, badgeActive: superLikeActive)
            if showsLocation {
                Text("\(profile.neighborhood), \(LocationPrivacy.rounded(km: profile.distanceKm))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
            }
        }
    }
}

/// (Optional super like disc,) name, then age, as one run of text: the disc leads at cap height,
/// the age follows the last word of the name at the name's x-height, even when the name wraps.
///
/// Long names are never truncated and never broken inside a word: the name wraps at spaces and
/// hyphens, and if a single word is wider than the space, the whole line steps down in size just
/// enough for it to fit. The disc is an inline image drawn by a text renderer, so it can pop in.
struct NameAgeLine: View {
    let profile: Profile
    var nameSize: CGFloat
    var nameColor: Color
    var ageColor: Color
    var showsBadge = false
    var badgeActive = true

    @State private var width: CGFloat = 0
    @State private var popped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scale: CGFloat { fittedScale(in: width) }

    /// Age sized so its figures stand as tall as the name's lowercase letters (x-height).
    private var ageRatio: CGFloat {
        guard let name = UIFont(name: DisplayFont.black, size: 100),
              let age = UIFont(name: DisplayFont.extraBold, size: 100), age.capHeight > 0 else { return 0.7 }
        return name.xHeight / age.capHeight
    }

    var body: some View {
        let n = nameSize * scale, a = nameSize * ageRatio * scale
        // The disc leads the line, exactly as tall as the capitals, sitting on the baseline.
        let badge = capHeight(n)
        var line = Text(verbatim: "")
        if showsBadge {
            line = Text(Image(uiImage: SuperLikeBadgeImage.image(size: badge)))
                    .customAttribute(BadgePop())
                + Text(verbatim: "\u{00A0}")
        }
        line = line
            + Text(profile.name).font(.display(n)).foregroundStyle(nameColor)
            + Text(verbatim: "\u{00A0}\u{00A0}\(profile.age)")
                .font(.displayBold(a, relativeTo: .largeTitle))
                .foregroundStyle(ageColor)
        return line
            .displayLeading(n)
            .textRenderer(BadgePopRenderer(progress: showsBadge ? (popped ? 1 : 0) : 1))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .accessibilityElement()
            .accessibilityLabel(showsBadge ? L("\(profile.name), \(profile.age), super liked you") : L("\(profile.name), \(profile.age)"))
            .onAppear { if badgeActive { pop() } }
            .onChange(of: badgeActive) { _, on in if on { pop() } }
    }

    private func pop() {
        guard showsBadge, !popped else { return }
        if reduceMotion { popped = true; return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.55).delay(0.12)) { popped = true }
    }

    // MARK: Fitting

    private func scaled(_ size: CGFloat) -> CGFloat {
        UIFontMetrics(forTextStyle: .largeTitle).scaledValue(for: size)
    }

    private func capHeight(_ size: CGFloat) -> CGFloat {
        UIFont(name: DisplayFont.black, size: scaled(size))?.capHeight ?? scaled(size) * 0.73
    }

    private func textWidth(_ text: String, font: String, size: CGFloat) -> CGFloat {
        guard let f = UIFont(name: font, size: scaled(size)) else { return 0 }
        return (text as NSString).size(withAttributes: [.font: f]).width
    }

    /// Unbreakable pieces of the name: split at spaces, and after hyphens.
    private var words: [String] {
        var out: [String] = [], current = ""
        for ch in profile.name {
            if ch == " " {
                if !current.isEmpty { out.append(current) }
                current = ""
            } else {
                current.append(ch)
                if ch == "-" { out.append(current); current = "" }
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// Widest unbreakable run at full size: any word, or the last word + age (+ disc) glued together.
    private var widestRun: CGFloat {
        var widths = words.map { textWidth($0, font: DisplayFont.black, size: nameSize) }
        guard !widths.isEmpty else { return 0 }
        // The disc is glued to the first word, the age to the last.
        if showsBadge {
            widths[0] += capHeight(nameSize) + textWidth("\u{00A0}", font: DisplayFont.black, size: nameSize)
        }
        widths[widths.count - 1] += textWidth("\u{00A0}\u{00A0}\(profile.age)", font: DisplayFont.extraBold,
                                              size: nameSize * ageRatio)
        return widths.max() ?? 0
    }

    private func fittedScale(in width: CGFloat) -> CGFloat {
        guard width > 0 else { return 1 }
        let widest = widestRun
        guard widest > width - 2 else { return 1 }
        return max(0.55, (width - 2) / widest)
    }
}

/// Marks the inline super like disc inside a name line.
struct BadgePop: TextAttribute {}

/// Draws a name line as is, except the super like disc, which scales and rotates in with `progress`.
struct BadgePopRenderer: TextRenderer, Animatable {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        for line in layout {
            for run in line {
                guard run[BadgePop.self] != nil, progress < 1 else {
                    ctx.draw(run)
                    continue
                }
                let r = run.typographicBounds.rect
                var c = ctx
                let s = 0.2 + 0.8 * progress
                c.opacity = min(1, max(0, progress * 1.6))
                c.translateBy(x: r.midX, y: r.midY)
                c.rotate(by: .degrees(-30 * (1 - progress)))
                c.scaleBy(x: s, y: s)
                c.translateBy(x: -r.midX, y: -r.midY)
                c.draw(run)
            }
        }
    }
}

/// The super like disc rendered once per size, for use inline in text.
@MainActor
enum SuperLikeBadgeImage {
    private static var cache: [Int: UIImage] = [:]

    static func image(size: CGFloat) -> UIImage {
        let key = Int(size.rounded())
        if let img = cache[key] { return img }
        let view = SuperLikeMark(size: size * 0.38, color: .white)
            .offset(x: -size * 0.09)
            .frame(width: size, height: size)
            .background(DS.Palette.negative, in: .circle)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let img = renderer.uiImage ?? UIImage()
        cache[key] = img
        return img
    }
}

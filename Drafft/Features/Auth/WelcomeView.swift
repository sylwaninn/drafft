import SwiftUI

struct WelcomeView: View {
    @State private var route: [AuthRoute] = []
    /// Framed portrait crops, women and men alternating. The splash shows the same ones.
    static let photos = ["hero_1", "hero_2", "hero_3", "hero_4", "hero_5", "hero_6"]
    /// Per photo, the height (0 top, 1 bottom) of the athlete: the face and upper body, or the
    /// whole rider when they are small in the frame. `FocusedPhoto` lifts it into the clear band
    /// between the wordmark and the panel.
    static let focus: [String: CGFloat] = [
        "hero_1": 0.48, "hero_2": 0.45, "hero_3": 0.52, "hero_4": 0.3, "hero_5": 0.52, "hero_6": 0.72
    ]

    var body: some View {
        NavigationStack(path: $route) {
            ZStack(alignment: .bottom) {
                DS.Palette.night.ignoresSafeArea()
                // The photo runs edge to edge, as on the splash: the panel floats on it.
                HeroSlideshow(photos: Self.photos)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                wordmark
                    .frame(maxHeight: .infinity, alignment: .top)
                panel
            }
            .navigationDestination(for: AuthRoute.self) { r in
                switch r {
                case .signUpEmail: SignUpView()
                case .logIn: LogInView()
                }
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
        // The stack's own background shows in the rounded corners during pushes: make it ours.
        .containerBackground(DS.Palette.night, for: .navigation)
        .tint(DS.Palette.accentInk)
    }

    private var wordmark: some View {
        // The plain word: no trail on a photo.
        Wordmark(color: .white, trailStrength: 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.xl)
            .safeAreaPadding(.top, DS.Space.lg)
            .background(alignment: .top) {
                // design-lint: allow gradient - photo scrim under the wordmark
                LinearGradient(stops: Self.easedScrim(peak: 0.75), startPoint: .bottom, endPoint: .top)
                .padding(.bottom, -72)
                .ignoresSafeArea(edges: .top)
            }
            .accessibilityHidden(true)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            Text("Match with people who train like you. Then meet on the track, the wall or the court.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Button("Sign up with email") { route.append(.signUpEmail) }
                .buttonStyle(.drafftPrimary)

            HStack(spacing: DS.Space.xs) {
                Text("Already training with us?")
                    .foregroundStyle(.white.opacity(0.72))
                Button("Log in") { route.append(.logIn) }
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.Palette.accentOnNight)
                    .buttonStyle(.textLink)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.top, DS.Space.xl)
        .padding(.bottom, DS.Space.sm)
        .background(alignment: .bottom) {
            // Sized by the panel, so it follows Dynamic Type and the language. An eased night scrim
            // (smoothstep, no visible edge) rises well above the words and carries their contrast;
            // the progressive blur starts just above the text, so the photo stays sharp down to it.
            ZStack(alignment: .bottom) {
                // design-lint: allow gradient - photo scrim under the panel
                LinearGradient(stops: Self.easedScrim(peak: 0.82), startPoint: .top, endPoint: .bottom)
                    .padding(.top, -120)
                ProgressiveBlur(edge: .bottom, maxRadius: 18)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .nightSurface()
    }

    /// Night from clear to `peak`, eased as a smoothstep so the scrim never shows where it starts.
    private static func easedScrim(peak: Double) -> [Gradient.Stop] {
        (0...10).map { i in
            let t = Double(i) / 10
            return .init(color: DS.Palette.night.opacity(peak * t * t * (3 - 2 * t)), location: t)
        }
    }
}

/// Photos rotating on their own, one quick crossfade every few seconds; nothing to swipe or tap.
struct HeroSlideshow: View {
    let photos: [String]
    var interval: Duration = .seconds(4)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index: Int

    init(photos: [String], interval: Duration = .seconds(4)) {
        self.photos = photos
        self.interval = interval
        _index = State(initialValue: Self.freshStart(count: photos.count))
    }

    /// A random first photo, never the one the previous slideshow opened on (even across launches).
    private static let lastStartKey = "heroSlideshow.lastStart"
    private static func freshStart(count: Int) -> Int {
        let last = UserDefaults.standard.object(forKey: lastStartKey) as? Int
        return (0..<count).filter { $0 != last }.randomElement() ?? 0
    }

    var body: some View {
        ZStack {
            ForEach(Array(photos.enumerated()), id: \.offset) { i, name in
                FocusedPhoto(name: name, focus: WelcomeView.focus[name] ?? 0.5)
                    .opacity(i == index ? 1 : 0)
            }
        }
        // Recorded once shown: a re-render's init only proposes a start, it never counts.
        .onAppear { UserDefaults.standard.set(index, forKey: Self.lastStartKey) }
        .task(id: index) {
            try? await Task.sleep(for: interval)
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) { index = (index + 1) % photos.count }
        }
    }
}

/// A photo filling its frame, its focus (the athlete) placed at 42 % of the frame: the clear band
/// between the wordmark and the panel. A photo with no height to spare (the heroes are exactly the
/// screen's size) is zoomed just enough to lift its focus there, at most 1.5x so it stays sharp;
/// it never shows past its edges, so the panel always sits on the bottom of the photo.
private struct FocusedPhoto: View {
    let name: String
    let focus: CGFloat
    private let target: CGFloat = 0.42
    private let maxZoom: CGFloat = 1.5

    var body: some View {
        GeometryReader { geo in
            if let img = ImageStore.preparedFull(name) ?? UIImage(named: name) {
                let fill = max(geo.size.width / img.size.width, geo.size.height / img.size.height)
                // Lowest zoom at which the focus reaches the target without uncovering the bottom.
                let needed = (1 - target) * geo.size.height / ((1 - focus) * img.size.height * fill)
                let scale = fill * min(maxZoom, max(1, needed))
                let w = img.size.width * scale
                let h = img.size.height * scale
                let y = min(0, max(geo.size.height - h, geo.size.height * target - focus * h))
                Image(uiImage: img)
                    .resizable()
                    .frame(width: w, height: h)
                    .offset(x: (geo.size.width - w) / 2, y: y)
            }
        }
        .clipped()
    }
}

enum AuthRoute: Hashable { case signUpEmail, logIn }

/// "drafft" set in the display face with a trailing ghost: the drafting motif from the app icon.
struct Wordmark: View {
    var size: CGFloat = 28
    var color: Color = DS.Palette.lime
    /// Ghost copy behind the lead word; defaults to a faded copy of the ink.
    var trail: Color?
    /// Scales both ghosts: 1 is the logo; lower keeps the motif quiet in the app's chrome.
    var trailStrength: Double = 1
    var body: some View {
        // Same as the logo: the word solid, two copies trailing behind it (20% and 45%).
        let ghost = trail ?? color
        ZStack(alignment: .leading) {
            Text(verbatim: "drafft").foregroundStyle(ghost.opacity(0.2 * trailStrength)).offset(x: -size * 0.21)
            Text(verbatim: "drafft").foregroundStyle(ghost.opacity(0.45 * trailStrength)).offset(x: -size * 0.104)
            Text(verbatim: "drafft").foregroundStyle(color)
        }
        .font(.display(size))
        .tracking(-size * 0.02)
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "drafft"))
    }
}

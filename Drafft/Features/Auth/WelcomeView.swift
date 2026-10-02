import SwiftUI

struct WelcomeView: View {
    @State private var route: [AuthRoute] = []
    /// Framed portrait crops, women and men alternating. The splash shows the same ones.
    static let photos = ["hero_1", "hero_2", "hero_3", "hero_4", "hero_5", "hero_6"]
    /// Per photo, its own framing: a point of the photo (the athlete) pinned to a point of the
    /// screen, zoomed in so it can move. The band between the wordmark and the panel (12 to 64 %
    /// of the height) is where the athlete reads; each photo is framed its own way, and some let a
    /// hand, a hold or a face run past the edge on purpose.
    static let framing: [String: PhotoFraming] = [
        // Tennis: the player whole, face and swing in the band.
        "hero_1": .init(zoom: 1.12, focus: UnitPoint(x: 0.5, y: 0.48), at: UnitPoint(x: 0.5, y: 0.42)),
        "hero_2": .init(zoom: 1.05, focus: UnitPoint(x: 0.5, y: 0.45), at: UnitPoint(x: 0.5, y: 0.42)),
        // Marathon: a close portrait, off-centre, her waving hand cut by the left edge.
        "hero_3": .init(zoom: 1.45, focus: UnitPoint(x: 0.62, y: 0.46), at: UnitPoint(x: 0.62, y: 0.36)),
        // Selfie: a close portrait, goggles and beanie in the band, the thumb cut by the left edge.
        "hero_4": .init(zoom: 1.05, focus: UnitPoint(x: 0.5, y: 0.45), at: UnitPoint(x: 0.5, y: 0.38)),
        // Climbing: the whole climber on the rock, her reach and her feet in the band.
        "hero_5": .init(zoom: 1.05, focus: UnitPoint(x: 0.5, y: 0.45), at: UnitPoint(x: 0.5, y: 0.42)),
        // Kayak: the paddler small on a calm lake, the mountains at the horizon, the bow in the panel.
        "hero_6": .init(zoom: 1.3, focus: UnitPoint(x: 0.45, y: 0.62), at: UnitPoint(x: 0.5, y: 0.52))
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
        Wordmark(color: .white)
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
            Text("Meet someone who gets your rhythm.")
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

/// Which hero photo is showing, shared by every slideshow: the splash hands over to the welcome
/// screen on the photo it was showing, and the welcome screen goes on from there.
@MainActor @Observable
final class HeroRotation {
    static let shared = HeroRotation(count: WelcomeView.photos.count)

    var index: Int

    /// A random first photo, never the one the previous launch opened on.
    private static let lastStartKey = "heroSlideshow.lastStart"
    private init(count: Int) {
        let last = UserDefaults.standard.object(forKey: Self.lastStartKey) as? Int
        index = (0..<count).filter { $0 != last }.randomElement() ?? 0
        UserDefaults.standard.set(index, forKey: Self.lastStartKey)
    }
}

extension EnvironmentValues {
    /// False while another slideshow covers this one (the welcome screen under the splash): it
    /// shows the shared photo but leaves the turning to the one on top.
    @Entry var heroSlideshowLeads = true
}

/// Photos rotating on their own, one quick crossfade every few seconds; nothing to swipe or tap.
struct HeroSlideshow: View {
    let photos: [String]
    var interval: Duration = .seconds(4)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.heroSlideshowLeads) private var leads
    @State private var rotation = HeroRotation.shared

    var body: some View {
        ZStack {
            ForEach(Array(photos.enumerated()), id: \.offset) { i, name in
                FocusedPhoto(name: name, framing: WelcomeView.framing[name] ?? PhotoFraming())
                    .opacity(i == rotation.index ? 1 : 0)
            }
        }
        // Restarts on every turn and when this slideshow takes the lead: a full interval each time.
        .task(id: "\(rotation.index)-\(leads)") {
            guard leads else { return }
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
                rotation.index = (rotation.index + 1) % photos.count
            }
        }
    }
}

/// How a photo sits in its frame: filled, zoomed by `zoom`, with its `focus` point moved to the
/// frame's `at` point as far as the photo's edges allow (it never shows past them).
struct PhotoFraming {
    var zoom: CGFloat = 1
    var focus = UnitPoint.center
    var at = UnitPoint.center
}

private struct FocusedPhoto: View {
    let name: String
    let framing: PhotoFraming

    var body: some View {
        GeometryReader { geo in
            if let img = ImageStore.preparedFull(name) ?? UIImage(named: name) {
                let fill = max(geo.size.width / img.size.width, geo.size.height / img.size.height)
                let w = img.size.width * fill * framing.zoom
                let h = img.size.height * fill * framing.zoom
                let x = min(0, max(geo.size.width - w, geo.size.width * framing.at.x - framing.focus.x * w))
                let y = min(0, max(geo.size.height - h, geo.size.height * framing.at.y - framing.focus.y * h))
                Image(uiImage: img)
                    .resizable()
                    .frame(width: w, height: h)
                    .offset(x: x, y: y)
            }
        }
        .clipped()
    }
}

enum AuthRoute: Hashable { case signUpEmail, logIn }

/// The logo: "drafft" set in the display face, solid.
struct Wordmark: View {
    var size: CGFloat = 28
    var color: Color = DS.Palette.lime
    var body: some View {
        Text(verbatim: "drafft")
            .foregroundStyle(color)
            .font(.display(size))
            .tracking(-size * 0.02)
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel(Text(verbatim: "drafft"))
    }
}

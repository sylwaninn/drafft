import SwiftUI

struct WelcomeView: View {
    @Environment(AppModel.self) private var app

    @State private var route: [AuthRoute] = []
    /// Framed portrait crops, women and men alternating. The splash shows the same ones.
    static let photos = ["hero_1", "hero_2", "hero_3", "hero_4", "hero_5", "hero_6"]
    /// Per photo, the height (0 top, 1 bottom) of what must stay in view when the frame is shorter
    /// than the photo, as in the log-in's hero: the head and body of each athlete.
    static let focus: [String: CGFloat] = [
        "hero_1": 0.5, "hero_2": 0.45, "hero_3": 0.55, "hero_4": 0.3, "hero_5": 0.45, "hero_6": 0.45
    ]


    var body: some View {
        NavigationStack(path: $route) {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    DS.Palette.night.ignoresSafeArea()

                    hero(height: geo.size.height * 0.68 + geo.safeAreaInsets.top)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .ignoresSafeArea(edges: .top)

                    panel
                }
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

    private func hero(height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            HeroSlideshow(photos: Self.photos)
            // design-lint: allow gradient - photo scrim under the wordmark
            LinearGradient(
                // Eased top scrim, deep enough under the wordmark for any photo.
                stops: [.init(color: DS.Palette.night.opacity(0.78), location: 0),
                        .init(color: DS.Palette.night.opacity(0.55), location: 0.12),
                        .init(color: DS.Palette.night.opacity(0.25), location: 0.24),
                        .init(color: DS.Palette.night.opacity(0.08), location: 0.34),
                        .init(color: .clear, location: 0.42),
                        // Bottom: a long eased fade (smoothstep), so the photo melts into the
                        // panel with no visible edge.
                        .init(color: .clear, location: 0.6),
                        .init(color: DS.Palette.night.opacity(0.04), location: 0.66),
                        .init(color: DS.Palette.night.opacity(0.14), location: 0.72),
                        .init(color: DS.Palette.night.opacity(0.3), location: 0.78),
                        .init(color: DS.Palette.night.opacity(0.5), location: 0.84),
                        .init(color: DS.Palette.night.opacity(0.7), location: 0.89),
                        .init(color: DS.Palette.night.opacity(0.86), location: 0.93),
                        .init(color: DS.Palette.night.opacity(0.96), location: 0.97),
                        .init(color: DS.Palette.night, location: 1)],
                startPoint: .top, endPoint: .bottom
            )
            Wordmark(color: .white, trail: DS.Palette.night)
                // Soft halo: keeps the white legible on bright photos without a visible box.
                .shadow(color: DS.Palette.night.opacity(0.45), radius: 12, y: 2)
                .padding(.horizontal, DS.Space.xl)
                .safeAreaPadding(.top, 64)
        }
        .frame(height: height)
        .clipped()
        .accessibilityHidden(true)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                Text("Match with people who train like you. Then meet on the track, the wall or the court.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: DS.Space.sm + 2) {
                Button("Sign up with email") { route.append(.signUpEmail) }
                    .buttonStyle(.drafftPrimary)
            }

            HStack(spacing: DS.Space.xs) {
                Text("Already training with us?")
                    .foregroundStyle(.white.opacity(0.6))
                Button("Log in") { route.append(.logIn) }
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.Palette.lime)
                    .buttonStyle(.textLink)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.bottom, DS.Space.sm)
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

/// A photo filling its frame, cropped around a focus height rather than its centre: the focus sits
/// at 40 % of the frame, without ever showing past the photo's edges.
private struct FocusedPhoto: View {
    let name: String
    let focus: CGFloat

    var body: some View {
        GeometryReader { geo in
            if let img = ImageStore.preparedFull(name) ?? UIImage(named: name) {
                let scale = max(geo.size.width / img.size.width, geo.size.height / img.size.height)
                let h = img.size.height * scale
                let y = min(0, max(geo.size.height - h, geo.size.height * 0.4 - focus * h))
                Image(uiImage: img)
                    .resizable()
                    .frame(width: img.size.width * scale, height: h)
                    .offset(x: (geo.size.width - img.size.width * scale) / 2, y: y)
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
    var body: some View {
        // Same as the logo: the word solid, two copies trailing behind it (20% and 45%).
        let ghost = trail ?? color
        ZStack(alignment: .leading) {
            Text(verbatim: "drafft").foregroundStyle(ghost.opacity(0.2)).offset(x: -size * 0.21)
            Text(verbatim: "drafft").foregroundStyle(ghost.opacity(0.45)).offset(x: -size * 0.104)
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

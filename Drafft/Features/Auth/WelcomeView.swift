import SwiftUI

struct WelcomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var route: [AuthRoute] = []
    @State private var pending: Provider?
    @State private var providerSheet: SocialIdentity.Provider?
    @State private var photoIndex = 0

    static let photos = ["sport_sunsetrun", "sport_boulder", "sport_clay", "sport_swim"]
    private let photos = WelcomeView.photos

    enum Provider { case apple, google }

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
        .sheet(item: $providerSheet) { p in
            Group {
                SocialSignInSheet(provider: p) { identity in
                    pending = p == .apple ? .apple : .google
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        pending = nil
                        app.signIn(with: identity)
                    }
                }
            }
            .sheetSurface()
        }
        .tint(DS.Palette.accentInk)
    }

    /// Session photos rotate on their own, one crossfade every few seconds.
    private func show(_ i: Int) {
        let next = (i + photos.count) % photos.count
        guard next != photoIndex else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) { photoIndex = next }
    }

    private func hero(height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(photos.enumerated()), id: \.offset) { i, name in
                Photo(name: name)
                    .opacity(i == photoIndex ? 1 : 0)
            }
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
            Wordmark(color: .white, trail: DS.Palette.lime)
                // Soft halo: keeps the white legible on bright photos without a visible box.
                .shadow(color: DS.Palette.night.opacity(0.45), radius: 12, y: 2)
                .padding(.horizontal, DS.Space.xl)
                .safeAreaPadding(.top, 64)
        }
        .frame(height: height)
        .clipped()
        // Photos rotate on their own; nothing to swipe or tap here.
        .task(id: photoIndex) {
            try? await Task.sleep(for: .seconds(4))
            show(photoIndex + 1)
        }
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
                Button {
                    socialSignIn(.apple)
                } label: {
                    providerLabel(.apple, text: L("Continue with Apple")) {
                        Image(systemName: "apple.logo").font(.title3)
                    }
                }
                .buttonStyle(ProviderButtonStyle(background: .white, foreground: .black))

                Button {
                    socialSignIn(.google)
                } label: {
                    providerLabel(.google, text: L("Continue with Google")) {
                        GoogleMark(size: 18)
                    }
                }
                .buttonStyle(ProviderButtonStyle(background: DS.Palette.nightRaised, foreground: .white, border: .white.opacity(0.18)))

                Button("Sign up with email") { route.append(.signUpEmail) }
                    .buttonStyle(.drafftPrimary)
            }
            .disabled(pending != nil)

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

    @ViewBuilder
    private func providerLabel(_ p: Provider, text: String, @ViewBuilder icon: () -> some View) -> some View {
        HStack(spacing: DS.Space.sm + 2) {
            if pending == p {
                ProgressView().tint(p == .apple ? .black : .white)
                Text("Connecting…")
            } else {
                icon()
                Text(text)
            }
        }
    }

    /// Demo: the provider's sheet is simulated and returns only what Apple / Google really share.
    private func socialSignIn(_ p: Provider) {
        Haptics.tap()
        providerSheet = p == .apple ? .apple : .google
    }
}

enum AuthRoute: Hashable { case signUpEmail, logIn }

struct ProviderButtonStyle: ButtonStyle {
    var background: Color
    var foreground: Color
    var border: Color = .clear

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            // A long translation takes a second, centred line, never "…".
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.9)
            .padding(.vertical, DS.Space.xs)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(foreground)
            .background(background, in: .rect(cornerRadius: DS.Radius.xl))
            .overlay { RoundedRectangle(cornerRadius: DS.Radius.xl).strokeBorder(border, lineWidth: 1) }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
            .contentShape(.rect(cornerRadius: DS.Radius.xl))
    }
}

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

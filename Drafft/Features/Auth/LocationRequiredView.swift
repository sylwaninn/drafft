import CoreLocation
import SwiftUI
import UIKit

/// Blocking screen when drafft can't use the location: it shows people near you, so it can't be used
/// without it. Precise or approximate doesn't matter; "While Using the App" is enough. No close button:
/// it goes away by itself once location is on, and says the one way there for the case at hand.
struct LocationRequiredView: View {
    @State private var location = LocationGate.shared
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// Location Services off for the whole phone, the app's permission refused, or never answered
    /// ("Ask Next Time" puts it back there): each has its own way back.
    private enum Case { case servicesOff, refused, notAsked }

    private var situation: Case {
        if location.servicesOff { return .servicesOff }
        return location.status == .notDetermined ? .notAsked : .refused
    }

    private var message: String {
        switch situation {
        case .servicesOff: L("Location Services are off on this iPhone. Turn them on in Settings, under Privacy & Security.")
        case .refused, .notAsked:
            L("drafft needs it to show people near you. While Using the App is enough, and only your area is ever shown.")
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    Spacer(minLength: DS.Space.lg)
                    EmptyStateIllustration(art: EmptyStateArt(symbol: "map-point-remove"), tint: DS.Palette.accentOnNight)
                        .offset(x: -73) // (200 - 54) / 2: the sign sits in the middle of its 200 pt map
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .rise(appeared, step: 0, reduceMotion: reduceMotion)
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        Text("Turn location back on.")
                            .font(.display(40))
                            .displayLeading(40)
                            .foregroundStyle(DS.Palette.accentOnNight)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text(branded: message, font: .body)
                            .foregroundStyle(.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .rise(appeared, step: 1, reduceMotion: reduceMotion)
                    if situation == .refused {
                        steps.rise(appeared, step: 2, reduceMotion: reduceMotion)
                    }
                }
                .padding(.horizontal, DS.Space.xl)
                .padding(.top, DS.Space.md)
                .padding(.bottom, DS.Space.xl)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .nightSurface()
        .safeAreaInset(edge: .bottom, spacing: 0) { action }
        .background(Color.black.ignoresSafeArea())
        .trackScreen(.locationRequired)
        .animation(Motion.snappy, value: location.servicesOff)
        .animation(Motion.snappy, value: location.status)
        .onAppear { appeared = true }
    }

    /// The way back once the permission was refused: Settings opens on drafft's own page.
    private var steps: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            step(1, L("Tap Location"))
            step(2, L("Pick While Using the App"))
        }
        .padding(DS.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.nightRaised, in: .rect(cornerRadius: DS.Radius.xl))
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(spacing: DS.Space.md) {
            Text(verbatim: "\(n)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.1), in: .circle)
                .accessibilityHidden(true)
            Text(branded: text, font: .subheadline.weight(.medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// Pinned at the bottom: the system prompt while it can still show, Settings otherwise.
    private var action: some View {
        Group {
            if situation == .notAsked {
                Button { location.request() } label: { Label("Allow location", image: "map-point") }
            } else {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Label("Open Settings", image: "settings")
                }
            }
        }
        .buttonStyle(.drafftPrimary)
        .padding(.horizontal, DS.Space.xl)
        .padding(.top, DS.Space.sm)
        .padding(.bottom, DS.Space.xs)
        .background(Color.black)
        .nightSurface()
        .rise(appeared, step: 3, reduceMotion: reduceMotion)
    }
}

// MARK: - Window

/// The location screen lives in its own window, above everything the app shows (sheets, covers, the
/// keyboard, top banners), so it covers the app whatever is open when location goes off. Only the
/// hold screen sits above it.
@MainActor
final class LocationWindow {
    static let shared = LocationWindow()
    private var window: UIWindow?
    private var hideTask: Task<Void, Never>?

    func update(visible: Bool, language: Locale) {
        hideTask?.cancel()
        if visible {
            guard let window = window ?? makeWindow() else { return }
            // The app's language as it is now (the window outlives a change of it).
            (window.rootViewController as? LocationHostingController)?.rootView = Self.content(language)
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            window.alpha = 1
            window.isHidden = false
            // Under a hold, its screen (above) keeps the keyboard focus.
            if AccountModeration.shared.hold == nil { window.makeKey() }
        } else if let window, !window.isHidden {
            // Fades out, then back to the app, where the person was.
            UIView.animate(withDuration: 0.3) { window.alpha = 0 }
            hideTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                window.isHidden = true
                if AccountModeration.shared.hold == nil { TopOverlayWindow.appWindow?.makeKey() }
            }
        }
    }

    private static func content(_ language: Locale) -> AnyView {
        AnyView(LocationRequiredView()
            // Its own window, outside the app's root: the app's language is set again here.
            .environment(\.locale, language)
            .tint(DS.Palette.accentInk)
            .noScrollIndicators())
    }

    private func makeWindow() -> UIWindow? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return nil }
        let window = LocationUIWindow(windowScene: scene)
        // Above the top banners (.alert + 1), under the hold screen (.alert + 2).
        window.windowLevel = .alert + 1.5
        window.backgroundColor = .black
        let host = LocationHostingController(rootView: AnyView(EmptyView()))
        host.view.backgroundColor = .black
        window.rootViewController = host
        self.window = window
        return window
    }
}

final class LocationUIWindow: UIWindow {}

/// Light status bar over the black page.
private final class LocationHostingController: UIHostingController<AnyView> {
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
}

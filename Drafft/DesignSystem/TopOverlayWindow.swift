import SwiftUI
import UIKit

/// A window above the app's own, for banners that must show over everything: sheets, covers,
/// the keyboard. Touches only land on the banner itself; everywhere else they pass to the app.
@MainActor
final class TopOverlayWindow {
    static let shared = TopOverlayWindow()
    private var window: PassThroughWindow?

    /// Screen frame of what's interactive in the overlay (the banner), set by the banner itself.
    var interactiveFrame: CGRect = .zero

    func install() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let window = PassThroughWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        let host = UIHostingController(rootView: TopOverlayContent())
        host.view.backgroundColor = .clear
        window.rootViewController = host
        // Visible, never key: the app's own window keeps the keyboard and the first responder.
        window.isHidden = false
        self.window = window
    }

    /// The app's own window (for presenting sheets), never this overlay or the hold screen's.
    static var appWindow: UIWindow? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            .filter { !($0 is PassThroughWindow) && !($0 is HoldUIWindow) }
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }
}

/// SwiftUI draws the whole overlay in one view, so hit testing goes by the banner's frame.
final class PassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let frame = MainActor.assumeIsolated { TopOverlayWindow.shared.interactiveFrame }
        guard frame.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

/// What the overlay shows: the photo-refused banner, at the top.
private struct TopOverlayContent: View {
    @State private var moderation = PhotoModeration.shared

    var body: some View {
        VStack {
            if let refusal = moderation.refusalBanner {
                PhotoRefusalBanner(refusal: refusal) {
                    moderation.refusalBanner = nil
                    PhotoRefusalPresenter.show(refusal)
                } onDismiss: {
                    withAnimation(Motion.snappy) { moderation.refusalBanner = nil }
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    TopOverlayWindow.shared.interactiveFrame = $0
                }
                .onDisappear { TopOverlayWindow.shared.interactiveFrame = .zero }
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, DS.Space.xs)
            }
            Spacer()
        }
        .animation(Motion.bouncy, value: moderation.refusalBanner)
        // Its own window, outside the app's root: the app's language is set again here.
        .environment(\.locale, .app)
    }
}

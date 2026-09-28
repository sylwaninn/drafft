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

/// What the overlay shows at the top: the photo-refused banner, a purchase on its way to the
/// account, calendar access refused when adding a session, or a session change the server turned down.
private struct TopOverlayContent: View {
    @State private var moderation = PhotoModeration.shared
    @State private var credit = PurchaseCredit.shared
    @State private var calendar = CalendarAccessNotice.shared
    @State private var sessionFailure = SessionFailureNotice.shared
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var slide: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }

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
                .transition(slide)
                .padding(.top, DS.Space.xs)
            } else if let state = credit.banner {
                PurchaseCreditBanner(state: state, pending: credit.oldest) {
                    credit.contactSupport()
                } onDismiss: {
                    withAnimation(Motion.snappy) { credit.dismissBanner() }
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    TopOverlayWindow.shared.interactiveFrame = $0
                }
                .onDisappear { TopOverlayWindow.shared.interactiveFrame = .zero }
                .transition(slide)
                .padding(.top, DS.Space.xs)
            } else if calendar.isShown {
                CalendarAccessBanner {
                    calendar.dismiss()
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } onDismiss: {
                    withAnimation(Motion.snappy) { calendar.dismiss() }
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    TopOverlayWindow.shared.interactiveFrame = $0
                }
                .onDisappear { TopOverlayWindow.shared.interactiveFrame = .zero }
                .transition(slide)
                .padding(.top, DS.Space.xs)
            } else if let message = sessionFailure.message {
                SessionFailureBanner(message: message) {
                    withAnimation(Motion.snappy) { sessionFailure.dismiss() }
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    TopOverlayWindow.shared.interactiveFrame = $0
                }
                .onDisappear { TopOverlayWindow.shared.interactiveFrame = .zero }
                .transition(slide)
                .padding(.top, DS.Space.xs)
            }
            Spacer()
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Motion.bouncy, value: moderation.refusalBanner)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Motion.bouncy, value: credit.banner)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Motion.bouncy, value: calendar.isShown)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Motion.bouncy, value: sessionFailure.message)
        // Its own window, outside the app's root: the app's language is set again here.
        .environment(\.locale, .app)
    }
}

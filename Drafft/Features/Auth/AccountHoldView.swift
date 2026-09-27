import SwiftUI
import UIKit

/// The whole app while the account is on hold: why, what it means, and the only ways out (a selfie
/// when one is asked, support, log out). No close button. A check that clears lets the person straight
/// back in, where they were.
struct AccountHoldView: View {
    let hold: AccountHold
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var askingHelp = false
    @State private var confirmingLogOut = false
    @State private var takingSelfie = false
    /// Tests: `-selfieDemo <step>` (sample photo) or `-openSelfie` (real camera) open the selfie camera
    /// by themselves, once per launch, the first time the selfie hold shows.
    @MainActor private static var openedForTests = false

    private var title: String {
        switch hold {
        case .review: L("We're checking your account.")
        case .selfie: L("Show us it's you.")
        case .banned: L("Your account has been closed.")
        }
    }

    private var message: String {
        switch hold {
        case .review:
            L("Our team needs a little time to make sure your account follows the drafft rules. It usually takes less than 48 hours.")
        case .selfie:
            L("Our team needs a quick selfie to check that your photos are really you.")
        case .banned:
            L("It broke the drafft community rules. This decision is final.")
        }
    }

    private var points: [(icon: String, text: String)] {
        switch hold {
        case .review:
            [("eye.slash.fill", L("Your profile is hidden while we check.")),
             ("bubble.left.and.bubble.right.fill", L("Your matches and chats are kept.")),
             ("lock.open.fill", L("The app opens again by itself once it's done."))]
        case .selfie:
            [("person.crop.square.fill", L("Just your face, well lit, nothing covering it.")),
             ("lock.fill", L("Only the drafft team sees it, never other members.")),
             ("eye.slash.fill", L("Your profile is hidden until then."))]
        case .banned:
            [("eye.slash.fill", L("Your profile and chats are no longer visible.")),
             ("person.crop.circle.badge.xmark", L("You can't create a new drafft account."))]
        }
    }

    private var art: EmptyStateArt {
        switch hold {
        case .review: .holdReview
        case .selfie: .holdSelfie
        case .banned: .holdClosed
        }
    }

    private var tint: Color { hold == .banned ? DS.Palette.negative : DS.Palette.lime }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    Wordmark(size: 26, color: .white, trail: DS.Palette.lime)
                        .accessibilityHidden(true)
                        .rise(appeared, step: 0, reduceMotion: reduceMotion)
                    Spacer(minLength: DS.Space.lg)
                    // The empty screens' sign in the terrain, its outline lined up with the text.
                    EmptyStateIllustration(art: art, tint: tint, strength: 2.6)
                        .offset(x: -73) // (200 - 54) / 2: the sign sits in the middle of its 200 pt map
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .rise(appeared, step: 1, reduceMotion: reduceMotion)
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        Text(title)
                            .font(.display(40))
                            .displayLeading(40)
                            .foregroundStyle(hold == .banned ? .white : DS.Palette.lime)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text(branded: message, font: .body)
                            .foregroundStyle(.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .rise(appeared, step: 2, reduceMotion: reduceMotion)
                    pointsBlock
                        .rise(appeared, step: 3, reduceMotion: reduceMotion)
                }
                .padding(.horizontal, DS.Space.xl)
                .padding(.top, DS.Space.md)
                .padding(.bottom, DS.Space.xl)
                // At least the screen's height: the wordmark at the top, the rest down by the buttons.
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        .background(DS.Palette.night.ignoresSafeArea())
        .onAppear {
            appeared = true
            let args = ProcessInfo.processInfo.arguments
            if hold == .selfie, !Self.openedForTests, args.contains("-selfieDemo") || args.contains("-openSelfie") {
                Self.openedForTests = true
                takingSelfie = true
            }
        }
        .sheet(isPresented: $askingHelp) {
            SupportSheet(topic: hold == .banned ? L("Closed account") : L("Account check"))
                .sheetSurface()
        }
        // Only while a selfie is asked: once it's sent, the hold turns to review and the camera goes with it.
        .fullScreenCover(isPresented: Binding(get: { takingSelfie && hold == .selfie }, set: { takingSelfie = $0 })) {
            SelfieCaptureView()
        }
        .drafftConfirm(isPresented: $confirmingLogOut, icon: "rectangle.portrait.and.arrow.right",
                       title: L("Log out?"),
                       message: hold == .selfie ? L("Log back in any time to send your selfie.")
                           : L("Log back in any time to see where the check is."),
                       actions: [ConfirmAction(title: L("Log out"), kind: .destructive) { app.signOut() }])
    }

    /// What the hold means, in one raised night block.
    private var pointsBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            ForEach(points, id: \.text) { point in
                HStack(spacing: DS.Space.md) {
                    Image(systemName: point.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.1), in: .circle)
                        .accessibilityHidden(true)
                    Text(branded: point.text, font: .subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(DS.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.nightRaised, in: .rect(cornerRadius: DS.Radius.xl))
    }

    /// Pinned at the bottom: the selfie when one is asked, help while in review, logging out once closed.
    private var actions: some View {
        VStack(spacing: DS.Space.xs) {
            switch hold {
            case .selfie:
                Button { takingSelfie = true } label: { Label("Take my selfie", systemImage: "camera.fill") }
                    .buttonStyle(.drafftPrimary)
                logOutLink
            case .review:
                Button { askingHelp = true } label: { Label("Get help", systemImage: "questionmark.bubble.fill") }
                    .buttonStyle(.drafftSecondary)
                logOutLink
            case .banned:
                Button { app.signOut() } label: {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.drafftSecondary)
                Button("A mistake? Contact us") { askingHelp = true }
                    .buttonStyle(.textLink(fullWidth: true))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.top, DS.Space.sm)
        .padding(.bottom, DS.Space.xs)
        .background(DS.Palette.night)
        .rise(appeared, step: 4, reduceMotion: reduceMotion)
    }

    private var logOutLink: some View {
        Button("Log out") { confirmingLogOut = true }
            .buttonStyle(.textLink(fullWidth: true))
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
    }
}

private extension EmptyStateArt {
    static let holdReview = EmptyStateArt(symbol: "hourglass", cutout: "hourglass", seed: "hold-review")
    static let holdClosed = EmptyStateArt(symbol: "nosign", cutout: "nosign", seed: "hold-closed")
    static let holdSelfie = EmptyStateArt(symbol: "faceid", cutout: "faceid", seed: "hold-selfie")
}

private extension View {
    /// Entrance: each part rises into place a beat after the one above it.
    func rise(_ appeared: Bool, step: Int, reduceMotion: Bool) -> some View {
        self
            .opacity(appeared || reduceMotion ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 14)
            .animation(Motion.bouncy.delay(0.06 * Double(step)), value: appeared)
    }
}

// MARK: - Window

/// The hold screen lives in its own window, above everything the app shows (sheets, covers, the
/// keyboard, banners), so it covers the app the moment the hold arrives, whatever is open.
@MainActor
final class HoldWindow {
    static let shared = HoldWindow()
    private var window: UIWindow?
    private var hideTask: Task<Void, Never>?

    func install(_ app: AppModel) {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let window = HoldUIWindow(windowScene: scene)
        window.windowLevel = .alert + 2
        window.backgroundColor = .clear
        let host = HoldHostingController(rootView: AnyView(HoldLayer().environment(app)))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        self.window = window
        update(visible: AccountModeration.shared.hold != nil)
    }

    func update(visible: Bool) {
        guard let window else { return }
        hideTask?.cancel()
        if visible {
            // Whatever was being typed gives way.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            window.isHidden = false
            window.makeKey()
        } else {
            // After the fade: back to the app, where the person was.
            hideTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                window.isHidden = true
                TopOverlayWindow.appWindow?.makeKey()
            }
        }
    }
}

final class HoldUIWindow: UIWindow {}

/// Light status bar over the night page.
private final class HoldHostingController: UIHostingController<AnyView> {
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
}

private struct HoldLayer: View {
    @Environment(AppModel.self) private var app
    @State private var moderation = AccountModeration.shared

    var body: some View {
        ZStack {
            if let hold = moderation.hold {
                AccountHoldView(hold: hold)
                    .id(hold)
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            }
        }
        .animation(Motion.gentle, value: moderation.hold)
        // Its own window, outside the app's root: the app's language is set again here.
        .environment(\.locale, app.language.locale)
        .tint(DS.Palette.accentInk)
    }
}

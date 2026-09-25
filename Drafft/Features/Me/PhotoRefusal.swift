import SwiftUI
import UIKit

/// Why a photo was refused, in plain words (never the detected labels), with what to do next:
/// ask a person for a second look, or take it off the profile.
struct PhotoRefusalSheet: View {
    let refusal: PhotoModeration.Refusal
    let dismiss: () -> Void
    /// Laid out without its scroll view, to measure the height the sheet opens at.
    var measuring = false
    @State private var sending = false
    @State private var sent = false
    @State private var error: String?

    var body: some View {
        if measuring {
            content
        } else {
            // Scrolls only if it's taller than the screen (large text, small phone): never cut.
            ScrollView { content }
                .scrollBounceBehavior(.basedOnSize)
                .background(DS.Palette.sheetRaised)
        }
    }

    /// Presented from UIKit, outside the app's root: the app's language is set again here.
    private var content: some View {
        layout.environment(\.locale, .app)
    }

    private var layout: some View {
        // The same space above the photo as between the photo and the title.
        VStack(spacing: DS.Space.xxl) {
            Photo(name: refusal.path)
                .frame(width: 96, height: 128)
                .clipShape(.rect(cornerRadius: DS.Radius.lg))
                .overlay {
                    // Their own photo, softened: the moment is about the decision, not the picture.
                    RoundedRectangle(cornerRadius: DS.Radius.lg).fill(.black.opacity(0.25))
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: sent ? "hourglass" : "nosign")
                        .font(.footnote.weight(.heavy))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(sent ? DS.Palette.night : DS.Palette.negative, in: .circle)
                        .offset(x: 8, y: 8)
                        .contentTransition(.symbolEffect(.replace))
                }
                .padding(.top, DS.Space.xxl)
                .accessibilityHidden(true)

            VStack(spacing: DS.Space.sm) {
                Text(sent ? "Thanks, we'll take a look" : "This photo can't go on your profile")
                    .font(.display(26, relativeTo: .title2))
                    .foregroundStyle(DS.Palette.ink)
                    .multilineTextAlignment(.center)
                    // Wraps instead of truncating.
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                Text(sent
                     ? "Someone from our team will review it, usually within 24 hours. It stays off your profile until then."
                     : "Our automatic check spotted something that doesn't fit our community guidelines, like nudity, violence or hateful symbols. Only you can see it. If we got it wrong, ask for a second look.")
                    .font(.body)
                    .foregroundStyle(DS.Palette.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                if let error {
                    Text(error)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DS.Palette.negative)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, DS.Space.xl)

            // The next steps.
            VStack(spacing: DS.Space.sm) {
                if sent {
                    Button("Got it") { dismiss() }
                        .buttonStyle(.drafftPrimary)
                } else {
                    Button("Remove this photo") {
                        PhotoModeration.shared.remove(refusal.path)
                        dismiss()
                    }
                    .buttonStyle(.drafftPrimary)
                    .disabled(sending)
                    Button {
                        Task { await askForReview() }
                    } label: {
                        if sending { ProgressView().tint(DS.Palette.ink) } else { Text("Ask for a second look") }
                    }
                    .buttonStyle(.drafftSecondary)
                    .disabled(sending)
                }
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.bottom, DS.Space.lg)
        }
        .frame(maxWidth: .infinity)
        .background(DS.Palette.sheetRaised)
        .animation(Motion.snappy, value: sent)
    }

    private func askForReview() async {
        sending = true
        error = nil
        do {
            try await PhotoModeration.shared.requestReview(refusal.path)
            Haptics.success()
            sent = true
        } catch {
            self.error = L("Couldn't send it. Check your connection and try again.")
        }
        sending = false
    }
}

/// In-app banner when a photo is refused (outside the app, a push says the same). Tap: the
/// explanation. Swipe up or wait: it goes away.
struct PhotoRefusalBanner: View {
    let refusal: PhotoModeration.Refusal
    let onOpen: () -> Void
    let onDismiss: () -> Void
    @State private var dragY: CGFloat = 0

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: DS.Space.md) {
                Photo(name: refusal.path)
                    .frame(width: 44, height: 56)
                    .clipShape(.rect(cornerRadius: DS.Radius.sm))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "nosign")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(DS.Palette.negative, in: .circle)
                            .offset(x: 6, y: 6)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text("A photo wasn't approved")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("It's not on your profile. Tap to see why.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Space.md)
            .padding(.trailing, DS.Space.sm)
            .modifier(BannerSurface())
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
        .offset(y: min(0, dragY))
        .gesture(
            DragGesture()
                .onChanged { dragY = $0.translation.height }
                .onEnded { v in
                    if v.translation.height < -30 { onDismiss() } else { withAnimation(Motion.snappy) { dragY = 0 } }
                }
        )
        .padding(.horizontal, DS.Space.md)
        .accessibilityHint("Explains why and what you can do")
        .task(id: refusal.id) {
            try? await Task.sleep(for: .seconds(6))
            onDismiss()
        }
    }
}

/// Shows the explanation above whatever is on screen (Edit profile, sign-up, a chat), without
/// closing it: a SwiftUI sheet from the app's root would have dismissed the screen already open.
@MainActor
enum PhotoRefusalPresenter {
    static func show(_ refusal: PhotoModeration.Refusal) {
        guard let root = TopOverlayWindow.appWindow?.rootViewController else { return }
        var top = root
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        // Already showing this one.
        if top is UIHostingController<PhotoRefusalSheet> { return }

        weak var presented: UIViewController?
        let host = UIHostingController(rootView: PhotoRefusalSheet(refusal: refusal) {
            presented?.dismiss(animated: true)
        })
        presented = host
        host.view.backgroundColor = UIColor(DS.Palette.sheetRaised)
        // Opens at exactly the height of its content (capped at the screen): nothing is cut.
        let width = TopOverlayWindow.appWindow?.bounds.width ?? UIScreen.main.bounds.width
        let fit = UIHostingController(rootView: PhotoRefusalSheet(refusal: refusal, dismiss: {}, measuring: true))
            .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.custom(identifier: .init("fit")) { context in min(fit, context.maximumDetentValue) }]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = DS.Radius.xl
        }
        top.present(host, animated: true)
    }
}

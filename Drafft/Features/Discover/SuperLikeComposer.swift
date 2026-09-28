import UIKit
import SwiftUI

/// Super like confirmation, shown in place over the deck like the profile's like composer: their
/// photo lifts forward on a dimmed, blurred background with a reminder of what a super like does,
/// an optional note, and the send button. Tap outside to cancel.
struct SuperLikeComposer: View {
    let profile: Profile
    let left: Int
    let onSend: (String) -> Void
    let onCancel: () -> Void

    @State private var message = ""
    @State private var appeared = false
    /// Set on the way out: nothing here takes touches while it fades.
    @State private var closing = false
    /// Tracked by hand: as an overlay on the tab's content, the composer doesn't get the
    /// system keyboard avoidance.
    @State private var keyboard: CGFloat = 0
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasMessage: Bool { !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(DS.Palette.night.opacity(0.5))
                .ignoresSafeArea()
                .opacity(appeared || reduceMotion ? 1 : 0)
                .onTapGesture { cancel() }
                .accessibilityLabel("Cancel super like")
                .accessibilityAddTraits(.isButton)

            // Content keeps its full height. With the keyboard up it anchors to the keyboard and
            // rises, sliding under the blurred header when there isn't room.
            VStack(spacing: DS.Space.md) {
                card
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.96)
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: DS.Space.sm) {
                    // One line only, so the send button never moves out of view.
                    TextField("Add a note (optional)", text: $message)
                        .lineLimit(1)
                        .font(.body)
                        .focused($focused)
                        .submitLabel(.send)
                        .onSubmit(send)
                        .padding(.horizontal, DS.Space.lg)
                        .padding(.vertical, 13)
                        .background(DS.Palette.canvas, in: .rect(cornerRadius: 22))

                    Button(action: send) {
                        HStack(spacing: DS.Space.sm) {
                            SuperLikeMark(size: 15, color: .white)
                            Text(hasMessage ? "Send super like with note" : "Send super like")
                                .contentTransition(.opacity)
                        }
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.9)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(DS.Palette.negative, in: .rect(cornerRadius: DS.Radius.xl))
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.97))
                    .draftTrail(RoundedRectangle(cornerRadius: DS.Radius.xl), color: DS.Palette.negative,
                                step: CGSize(width: -6, height: 0))
                    .padding(.leading, 12)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 12)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DS.Space.xl)
            .padding(.bottom, keyboard > 0 ? keyboard + DS.Space.md : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: keyboard > 0 ? .bottom : .center)
            // Always lay out against the full screen: the tab bar hiding as this opens changes the
            // safe area, and following it would make the content jump.
            .ignoresSafeArea(.container, edges: .bottom)

            // Header: progressive blur so content passing underneath fades out, close always on top.
            VStack(spacing: 0) {
                ProgressiveBlur(edge: .top)
                    .frame(height: 96)
                    .ignoresSafeArea(edges: .top)
                    .opacity(keyboard > 0 ? 1 : 0)
                    .animation(Motion.gentle, value: keyboard > 0)
                    .allowsHitTesting(false)
                Spacer()
            }

            VStack {
                HStack {
                    Spacer()
                    Button { cancel() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.18), in: .circle)
                    }
                    .accessibilityLabel("Cancel")
                }
                Spacer()
            }
            .padding(DS.Space.lg)
        }
        .ignoresSafeArea(.keyboard)
        .allowsHitTesting(!closing)
        .onAppear { withAnimation(.smooth(duration: 0.28)) { appeared = true } }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            // The notification's object is the screen the keyboard is on (UIScreen.main is deprecated).
            let screen = (note.object as? UIScreen)?.bounds.height ?? frame.minY
            withAnimation(Motion.snappy) { keyboard = max(0, screen - frame.minY) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(Motion.snappy) { keyboard = 0 }
        }
    }

    /// Their photo fills the whole profile block; toward the bottom it turns into a progressive
    /// blur tinted night, and the reminder sits on that frosted part. No hard band anywhere.
    private var card: some View {
        VStack(spacing: DS.Space.sm) {
            ProfileIdentity(profile: profile, nameSize: 30, showsLocation: false)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 240)
            remaining
            Text("\(profile.name) sees you first.")
                .font(.displayBold(22, relativeTo: .title3))
                .foregroundStyle(.white)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, DS.Space.xl)
        .padding(.top, DS.Space.lg)
        .padding(.bottom, DS.Space.xl)
        .frame(maxWidth: .infinity)
        .nightSurface()
        .background { backdrop }
        .clipShape(.rect(cornerRadius: DS.Radius.xl))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
        .accessibilityElement(children: .combine)
    }

    private var backdrop: some View {
        GeometryReader { geo in
            ZStack {
                Photo(name: profile.portrait)
                // Same photo, heavily blurred, revealed progressively toward the bottom.
                Photo(name: profile.portrait)
                    .blur(radius: 28, opaque: true)
                    // design-lint: allow gradient - blur mask over the photo
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0.66),
                                                 .init(color: .black.opacity(0.6), location: 0.76),
                                                 .init(color: .black, location: 0.84)],
                                         startPoint: .top, endPoint: .bottom))
                // Soft tint for legibility: light at the top for the name, deeper under the text.
                // design-lint: allow gradient - photo scrim for legibility
                LinearGradient(stops: [.init(color: DS.Palette.night.opacity(0.45), location: 0),
                                       .init(color: DS.Palette.night.opacity(0), location: 0.28),
                                       .init(color: DS.Palette.night.opacity(0), location: 0.64),
                                       .init(color: DS.Palette.night.opacity(0.35), location: 0.8),
                                       .init(color: DS.Palette.night.opacity(0.62), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// How many super likes are left after this one.
    private var remaining: some View {
        let after = left - 1
        return HStack(spacing: 6) {
            SuperLikeMark(size: 11, color: .white)
            // A pill stays on one line: the short wording takes over when the long one won't fit.
            ViewThatFits(in: .horizontal) {
                Text(after == 0 ? L("Your last super like")
                     : after == 1 ? L("1 super like left after this") : L("\(after) super likes left after this"))
                    .fixedSize()
                Text(after == 0 ? L("Your last super like")
                     : after == 1 ? L("1 super like left") : L("\(after) super likes left"))
                    .fixedSize()
            }
                .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.leading, DS.Space.sm)
        .padding(.trailing, DS.Space.md)
        .frame(minHeight: 30)
        .background(.white.opacity(0.1), in: .capsule)
    }

    private func send() {
        Haptics.success()
        let note = message.trimmingCharacters(in: .whitespacesAndNewlines)
        close { onSend(note) }
    }

    private func cancel() {
        Haptics.tap()
        close(then: onCancel)
    }

    /// Fades out, then hands back (the presenter removes it without its own animation).
    private func close(then done: @escaping () -> Void) {
        guard !closing else { return }
        closing = true
        focused = false
        withAnimation(.easeOut(duration: 0.16)) { appeared = false }
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 160))
            done()
        }
    }
}

import SwiftUI
import UIKit

/// Full-screen match moment: two portraits slide in, one tucked behind the other.
struct MatchView: View {
    let profile: Profile
    let me: Profile
    let onChat: () -> Void
    let onClose: () -> Void

    @State private var arrived = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shared: Sport? {
        profile.sports.map(\.sport).first { s in me.sports.contains { $0.sport == s } }
    }

    var body: some View {
        ZStack {
            DS.Palette.night.ignoresSafeArea()

            VStack(alignment: .leading, spacing: DS.Space.xl) {
                Spacer(minLength: DS.Space.lg)

                formation
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)

                VStack(alignment: .leading, spacing: DS.Space.md) {
                    Text("It's mutual.")
                        .font(.display(64))
                        .displayLeading(64)
                        .foregroundStyle(DS.Palette.accentOnNight)
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(arrived ? 1 : 0)
                .offset(y: arrived ? 0 : 24)

                Spacer()

                VStack(spacing: DS.Space.sm) {
                    Button {
                        onChat()
                    } label: {
                        Label("Say hi", image: "chat-round-line")
                    }
                    .buttonStyle(.drafftPrimary)
                    Button("Keep swiping", action: onClose)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .buttonStyle(.textLink(minHeight: 52, fullWidth: true))
                }
                .opacity(arrived ? 1 : 0)
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.bottom, DS.Space.sm)
            .nightSurface()
        }
        .onAppear {
            if reduceMotion {
                arrived = true
                return
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { arrived = true }
        }
        .trackScreen(.match)
    }

    private var subtitle: String {
        if let shared {
            return L("You and \(profile.name) both do \(shared.inSentence). Say hi, or propose a session while it's fresh.")
        }
        return L("\(profile.name) likes you too. Say hi, or propose a session while it's fresh.")
    }

    private var formation: some View {
        ZStack {
            portrait(me.portrait)
                .rotationEffect(.degrees(-6))
                .offset(x: arrived ? -48 : -260, y: -10)

            portrait(profile.portrait)
                .rotationEffect(.degrees(7))
                .offset(x: arrived ? 56 : 260, y: 24)

            // Liking stays green whatever the brand accent.
            Image("heart")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(DS.Palette.onLike)
                .frame(width: 64, height: 64)
                .background(DS.Palette.like, in: .circle)
                .overlay(Circle().strokeBorder(DS.Palette.night, lineWidth: 4))
                .scaleEffect(arrived ? 1 : 0.2)
                .offset(x: 4, y: 128)
                .symbolEffect(.bounce, value: arrived)
        }
        .accessibilityElement()
        .accessibilityLabel("Your photo and \(profile.name)'s photo")
    }

    private func portrait(_ name: String) -> some View {
        Photo(name: name, side: 170)
            .frame(width: 170, height: 230)
            .clipShape(.rect(cornerRadius: DS.Radius.xl))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.xl).strokeBorder(DS.Palette.night, lineWidth: 4))
    }
}

/// In-app notification when someone likes you back later.
struct MatchBannerView: View {
    let banner: AppModel.MatchBanner
    let onOpen: () -> Void
    let onDismiss: () -> Void
    @State private var dragY: CGFloat = 0

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: DS.Space.md) {
                Avatar(name: banner.profile.portrait, size: 48, ring: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(banner.profile.name) liked you back")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("It's mutual. Tap to say hi.")
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.accentOnNight)
                }
                Spacer(minLength: 0)
                Image("heart")
                    .foregroundStyle(DS.Palette.like)
                    .symbolEffect(.bounce, options: .repeat(2))
                    .accessibilityHidden(true)
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
        .accessibilityHint("Opens the chat")
        .task(id: banner.id) {
            try? await Task.sleep(for: .seconds(5))
            onDismiss()
        }
    }
}

/// Confirmation right after starting a boost: you're at the front of the pack for 30 minutes.
struct BoostBannerView: View {
    let id: UUID
    let onDismiss: () -> Void
    @State private var dragY: CGFloat = 0
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Image("bolt")
                .font(.title3.weight(.heavy))
                .foregroundStyle(DS.Palette.onAccentOnNight)
                .frame(width: 48, height: 48)
                .background(DS.Palette.accentOnNight, in: .circle)
                .background {
                    Circle()
                        .stroke(DS.Palette.accentOnNight, lineWidth: 2)
                        .scaleEffect(pulse ? 1.6 : 1)
                        .opacity(pulse ? 0 : 0.8)
                }
                .symbolEffect(.bounce, value: pulse)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're boosted")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("People nearby see you first for 30 minutes.")
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.accentOnNight)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.md)
        .padding(.trailing, DS.Space.sm)
        .modifier(BannerSurface())
        .offset(y: min(0, dragY))
        .gesture(
            DragGesture()
                .onChanged { dragY = $0.translation.height }
                .onEnded { v in
                    if v.translation.height < -30 { onDismiss() } else { withAnimation(Motion.snappy) { dragY = 0 } }
                }
        )
        .padding(.horizontal, DS.Space.md)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.7).delay(0.15)) { pulse = true }
        }
        .task(id: id) {
            try? await Task.sleep(for: .seconds(4))
            onDismiss()
        }
    }
}

/// A swipe, undo, unmatch or boost the server turned down (or that couldn't reach it): the reason, in
/// the person's language. Swipe it up, or it goes by itself.
struct NoticeBannerView: View {
    let notice: AppModel.Notice
    let onDismiss: () -> Void
    @State private var dragY: CGFloat = 0

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Image("exclamation-mark")
                .font(.title3.weight(.heavy))
                .foregroundStyle(DS.Palette.onAccentOnNight)
                .frame(width: 48, height: 48)
                .background(DS.Palette.accentOnNight, in: .circle)
                .accessibilityHidden(true)
            Text(notice.text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(DS.Space.md)
        .padding(.trailing, DS.Space.sm)
        .modifier(BannerSurface())
        .offset(y: min(0, dragY))
        .gesture(
            DragGesture()
                .onChanged { dragY = $0.translation.height }
                .onEnded { v in
                    if v.translation.height < -30 { onDismiss() } else { withAnimation(Motion.snappy) { dragY = 0 } }
                }
        )
        .padding(.horizontal, DS.Space.md)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .onAppear { UIAccessibility.post(notification: .announcement, argument: notice.text) }
        .task(id: notice.id) {
            try? await Task.sleep(for: .seconds(4))
            onDismiss()
        }
    }
}

/// Surface for in-app banners (match, boost, notices): solid night, a thin light rim and a layered
/// shadow, so it lifts off any page, light or dark. No gradient in the fill.
struct BannerSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .nightSurface()
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.xl)
                    .fill(DS.Palette.night)
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.xl)
                            .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                    }
            }
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            .shadow(color: .black.opacity(0.35), radius: 28, y: 16)
    }
}

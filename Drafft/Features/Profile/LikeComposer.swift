import SwiftUI

/// What a like points at.
enum LikeTarget: Identifiable, Hashable {
    case photo(String)
    case prompt(ProfilePrompt)
    var id: String {
        switch self {
        case .photo(let n): "photo-\(n)"
        case .prompt(let p): "prompt-\(p.question)"
        }
    }
}

/// Like composer shown in place, over the profile: the liked item lifts forward on a dimmed,
/// blurred background, with a comment field and the send button right under it. Tap outside to cancel.
struct LikeComposer: View {
    let target: LikeTarget
    let name: String
    let onSend: (String) -> Void
    let onCancel: () -> Void

    @State private var message = ""
    @State private var appeared = false
    /// Set on the way out: the veil stops taking touches the moment it starts fading, so a tap
    /// right after closing reaches the profile underneath.
    @State private var closing = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasMessage: Bool { !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(DS.Palette.night.opacity(0.45))
                .ignoresSafeArea()
                .opacity(appeared || reduceMotion ? 1 : 0)
                .onTapGesture { cancel() }
                .accessibilityLabel("Cancel like")
                .accessibilityAddTraits(.isButton)

            VStack(spacing: DS.Space.lg) {
                Spacer(minLength: 0)

                item
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.9)
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: DS.Space.sm) {
                    HStack(alignment: .bottom, spacing: DS.Space.sm) {
                        TextField("Add a comment", text: $message, axis: .vertical)
                            .lineLimit(1...4)
                            .font(.body)
                            .focused($focused)
                            .padding(.horizontal, DS.Space.lg)
                            .padding(.vertical, 13)
                            .background(DS.Palette.canvas, in: .rect(cornerRadius: 22))
                    }
                    Button {
                        Haptics.success()
                        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
                        close { onSend(text) }
                    } label: {
                        Label(hasMessage ? "Send like with comment" : "Send like", systemImage: "heart.fill")
                            .contentTransition(.opacity)
                    }
                    .buttonStyle(DrafftButtonStyle(kind: .like))
                    .draftTrail(RoundedRectangle(cornerRadius: DS.Radius.xl), color: DS.Palette.like, step: CGSize(width: -6, height: 0))
                    .padding(.leading, 12)
                    Text("\(name) only sees it if you match.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 20)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Space.xl)
            .nightSurface()

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
        .allowsHitTesting(!closing)
        .onAppear { withAnimation(Motion.bouncy) { appeared = true } }
    }

    @ViewBuilder
    private var item: some View {
        switch target {
        case .photo(let photo):
            Photo(name: photo)
                .frame(maxWidth: .infinity)
                .frame(height: focused ? 200 : 360)
                .clipShape(.rect(cornerRadius: DS.Radius.xl))
                .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
                .animation(Motion.snappy, value: focused)
        case .prompt(let p):
            VStack(alignment: .leading, spacing: DS.Space.md) {
                Text(p.questionText).font(.subheadline.weight(.semibold)).foregroundStyle(DS.Palette.body)
                Text(p.answer)
                    .font(.displayBold(26, relativeTo: .title2))
                    .foregroundStyle(DS.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
            .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
        }
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

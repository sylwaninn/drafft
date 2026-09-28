import SwiftUI

/// A message lifted out of the chat on long press, iMessage-style: the page blurs, the bubble
/// stays exactly where it was, a glass bar of reactions sits above it and the actions below.
struct FocusedMessage: Identifiable, Equatable {
    let message: Message
    /// The bubble's frame on screen when it was pressed.
    let frame: CGRect
    var id: String { message.id }
}

struct MessageFocusOverlay: View {
    let focus: FocusedMessage
    let convo: Conversation
    let onReact: (String) -> Void
    let onReply: () -> Void
    let onDismiss: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    /// On the way out, a second tap (outside, or on another reaction) does nothing.
    @State private var closing = false
    /// "+" in the reaction bar: any emoji from the keyboard.
    @State private var pickingEmoji = false

    static let reactions = ["❤️", "🔥", "😂", "👏", "😮", "💪"]

    private var message: Message { focus.message }
    private var mine: Bool { message.fromMe }
    private let barHeight: CGFloat = 56
    /// Your own messages take no reaction (the bar is only over theirs), so no room is kept for it.
    private var barSpace: CGFloat { mine ? 0 : barHeight + gap }
    private let gap: CGFloat = 10

    private var actions: [(title: String, icon: String, role: ButtonRole?, run: () -> Void)] {
        var out: [(String, String, ButtonRole?, () -> Void)] = [(L("Reply"), "arrowshape.turn.up.left", nil, onReply)]
        if case .text(let t) = message.content {
            out.append((L("Copy"), "doc.on.doc", nil, { UIPasteboard.general.string = t }))
        }
        if mine {
            out.append((L("Unsend"), "arrow.uturn.backward", .destructive, {
                withAnimation(Motion.snappy) { app.delete(message.id, in: convo.id) }
            }))
        }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            let safe = geo.safeAreaInsets
            let menuHeight = CGFloat(actions.count) * 48
            // Shrink very tall bubbles (session cards) so bar, bubble and menu all fit.
            let room = geo.size.height - safe.top - safe.bottom - barSpace - menuHeight - gap - 24
            let scale = min(1, room / max(focus.frame.height, 1))
            let h = focus.frame.height * scale
            let total = barSpace + h + gap + menuHeight
            // Keep the bubble where it was, unless that pushes the bar or menu off screen.
            let resting = min(max(focus.frame.minY - barSpace, safe.top + 12),
                              geo.size.height - safe.bottom - 12 - total)
            // With the emoji keyboard up (~360 pt), lift so the bar and bubble stay above it.
            let top = pickingEmoji
                ? max(safe.top + 12, min(resting, geo.size.height - 372 - barSpace - h))
                : resting

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(DS.Palette.night.opacity(0.18))
                    .ignoresSafeArea()
                    .opacity(shown ? 1 : 0)
                    .onTapGesture { close(then: onDismiss) }
                    .accessibilityLabel("Close")
                    .accessibilityAddTraits(.isButton)

                VStack(alignment: mine ? .trailing : .leading, spacing: gap) {
                    if !mine { reactionBar }
                    MessageRow(message: message, convo: convo, groupedWithNext: true,
                               onOpen: { _ in }, presentation: true)
                        .frame(width: focus.frame.width, height: focus.frame.height)
                        .scaleEffect(scale * (shown ? 1.02 : 1), anchor: .top)
                        .frame(width: focus.frame.width, height: h, alignment: .top)
                        .shadow(color: .black.opacity(shown ? 0.18 : 0), radius: 24, y: 10)
                        .allowsHitTesting(false)
                    menu
                        .opacity(pickingEmoji ? 0 : 1)
                }
                .frame(width: geo.size.width - DS.Space.md * 2, alignment: mine ? .trailing : .leading)
                .offset(x: DS.Space.md, y: top)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: pickingEmoji)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        // VoiceOver's scrub gesture closes it, like tapping outside.
        .accessibilityAction(.escape) { close(then: onDismiss) }
        .onAppear {
            Haptics.thump()
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.75)) { shown = true }
        }
    }

    /// Glass capsule of reactions; each pops in a beat after the previous one.
    private var reactionBar: some View {
        HStack(spacing: 2) {
            ForEach(Array(Self.reactions.enumerated()), id: \.element) { i, e in
                let on = message.reaction == e
                Button {
                    Haptics.select()
                    close { onReact(e) }
                } label: {
                    Text(e)
                        .font(.system(size: 28))
                        .frame(width: 44, height: 44)
                        .background(on ? DS.Palette.lime.opacity(0.9) : .clear, in: .circle)
                }
                .buttonStyle(PressScaleStyle(scale: 0.8))
                .scaleEffect(shown || reduceMotion ? 1 : 0.3)
                .opacity(shown ? 1 : 0)
                .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.6).delay(Double(i) * 0.025), value: shown)
                .accessibilityLabel(on ? "Remove \(e) reaction" : "React \(e)")
            }
            // Current reaction if it's not one of the six, then "+" for any emoji.
            if let r = message.reaction, !Self.reactions.contains(r) {
                Text(r)
                    .font(.system(size: 28))
                    .frame(width: 44, height: 44)
                    .background(DS.Palette.lime.opacity(0.9), in: .circle)
                    .contentShape(.circle)
                    .onTapGesture { close { onReact(r) } }
                    .accessibilityLabel("Remove \(r) reaction")
                    .accessibilityAddTraits(.isButton)
            }
            Button {
                Haptics.tap()
                pickingEmoji = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DS.Palette.ink)
                    .frame(width: 40, height: 40)
                    .background(DS.Palette.ink.opacity(pickingEmoji ? 0.14 : 0.07), in: .circle)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(PressScaleStyle(scale: 0.85))
            .scaleEffect(shown || reduceMotion ? 1 : 0.3)
            .opacity(shown ? 1 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.6).delay(0.16), value: shown)
            .accessibilityLabel("More emoji")
        }
        .background {
            EmojiInput(active: $pickingEmoji) { e in
                pickingEmoji = false
                Haptics.select()
                close { onReact(e) }
            }
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 6)
        .frame(height: barHeight)
        .glassEffect(.regular, in: .capsule)
        .scaleEffect(shown ? 1 : 0.85, anchor: mine ? .bottomTrailing : .bottomLeading)
        .opacity(shown ? 1 : 0)
    }

    private var menu: some View {
        VStack(spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.offset) { i, a in
                if i > 0 { Divider().padding(.leading, 48) }
                Button(role: a.role) {
                    close(then: { a.run(); onDismiss() })
                } label: {
                    HStack(spacing: DS.Space.md) {
                        Image(systemName: a.icon)
                            .font(.body.weight(.semibold))
                            .frame(width: 24)
                        Text(a.title).font(.body)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(a.role == .destructive ? DS.Palette.negative : DS.Palette.ink)
                    .padding(.horizontal, DS.Space.lg)
                    .frame(height: 48)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 230)
        .glassEffect(.regular, in: .rect(cornerRadius: DS.Radius.xl))
        .scaleEffect(shown ? 1 : 0.85, anchor: mine ? .topTrailing : .topLeading)
        .opacity(shown ? 1 : 0)
    }

    private func close(then done: @escaping () -> Void) {
        guard !closing else { return }
        closing = true
        withAnimation(.easeOut(duration: 0.14)) { shown = false }
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 140))
            done()
        }
    }
}

/// Invisible text field that opens straight on the emoji keyboard and hands back the first
/// emoji typed. Used by the reaction bar's "+".
struct EmojiInput: UIViewRepresentable {
    @Binding var active: Bool
    let onPick: (String) -> Void

    final class Field: UITextField {
        override var textInputMode: UITextInputMode? {
            UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
        }
    }

    func makeUIView(context: Context) -> Field {
        let f = Field()
        f.tintColor = .clear
        f.textColor = .clear
        f.autocorrectionType = .no
        f.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return f
    }

    func updateUIView(_ f: Field, context: Context) {
        context.coordinator.parent = self
        if active, !f.isFirstResponder {
            DispatchQueue.main.async { f.becomeFirstResponder() }
        } else if !active, f.isFirstResponder {
            DispatchQueue.main.async { f.resignFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject {
        var parent: EmojiInput
        init(parent: EmojiInput) { self.parent = parent }

        @objc func changed(_ f: UITextField) {
            guard let ch = f.text?.first(where: { $0.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.properties.isEmoji && $0.value > 0x238C } })
            else { f.text = ""; return }
            f.text = ""
            parent.onPick(String(ch))
        }
    }
}

import SwiftUI

/// "Get help" from anywhere a check fails: the topic and a reference are filled in, the person
/// adds a few words, and it goes to support. Demo: nothing is sent.
struct SupportSheet: View {
    let topic: String
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var sending = false
    @State private var sent = false
    @State private var reference = "DR-" + String(UUID().uuidString.prefix(6))
    @FocusState private var messageFocused: Bool

    /// Newlines count as empty too: the field is multi-line.
    private var hasMessage: Bool { !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        AccountSheet(title: L("Get help"),
                     actionTitle: sent ? L("Done") : L("Send to support"),
                     actionIcon: sent ? "checkmark" : "paperplane.fill",
                     enabled: sent || hasMessage,
                     loading: sending) {
            if sent { dismiss(); return }
            sending = true
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                sending = false
                Haptics.success()
                withAnimation(Motion.bouncy) { sent = true }
            }
        } content: {
            if sent {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Image(systemName: "checkmark")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(DS.Palette.onLime)
                        .frame(width: 48, height: 48)
                        .background(DS.Palette.lime, in: .circle)
                    Text("Message sent.")
                        .font(.display(28))
                        .foregroundStyle(.white)
                    Text("We'll reply at \(app.email). Your reference is \(reference).")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }
                .padding(DS.Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Palette.night, in: .rect(cornerRadius: DS.Radius.xl))
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            } else {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    HStack {
                        Text("Topic").font(.subheadline.weight(.semibold)).foregroundStyle(DS.Palette.body)
                        Spacer()
                        Text(topic).font(.subheadline.weight(.semibold)).foregroundStyle(DS.Palette.ink)
                    }
                    Divider()
                    HStack {
                        Text("Reference").font(.subheadline.weight(.semibold)).foregroundStyle(DS.Palette.body)
                        Spacer()
                        Text(reference).font(.subheadline.monospacedDigit()).foregroundStyle(DS.Palette.ink)
                    }
                }
                .padding(DS.Space.lg)
                .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))

                SheetBlock(title: L("What happened?")) {
                    TextField("A few words help us fix it faster", text: $message, axis: .vertical)
                        .lineLimit(4...8)
                        .font(.body)
                        .focused($messageFocused)
                        .revealsOnFocus(messageFocused)
                        .padding(DS.Space.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                        .onTapGesture { messageFocused = true }
                        .background(DS.Palette.field, in: .rect(cornerRadius: DS.Radius.md))
                        .overlay {
                            // Same focus ring as DrafftField.
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .strokeBorder(messageFocused ? DS.Palette.ink : DS.Palette.ink.opacity(0.35),
                                              lineWidth: messageFocused ? 2 : 1)
                        }
                        .animation(Motion.gentle, value: messageFocused)
                }
            }
        }
    }
}

/// Small "Get help" link shown under an error.
struct GetHelpButton: View {
    let topic: String
    @State private var show = false

    var body: some View {
        Button {
            Haptics.tap()
            show = true
        } label: {
            Label("Get help", systemImage: "questionmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.Palette.accentInk)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .sheet(isPresented: $show) { Group { SupportSheet(topic: topic) }.sheetSurface() }
    }
}

/// A support topic, for `.sheet(item:)`.
struct HelpTopic: Identifiable, Hashable { let id: String }

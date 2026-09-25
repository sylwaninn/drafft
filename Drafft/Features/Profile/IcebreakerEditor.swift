import SwiftUI

/// Edit the interactive prompt in place: the card you edit is the card they'll see.
/// Formats sit in a compact switcher above it; each format edits its own fields inside the card.
struct IcebreakerEditor: View {
    @Binding var icebreaker: Icebreaker

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            formatSwitcher
            card
        }
    }

    // MARK: Format switcher

    /// Format select: a field-like button that opens a native menu of the five formats.
    private var formatSwitcher: some View {
        Menu {
            Picker("Format", selection: Binding(get: { icebreaker.kind }, set: { kind in
                guard kind != icebreaker.kind else { return }
                Haptics.select()
                withAnimation(Motion.snappy) { icebreaker = kind.blank }
            })) {
                ForEach(Icebreaker.Kind.allCases) { kind in
                    Label {
                        Text(kind.title)
                        Text(kind.detail)
                    } icon: {
                        Image(systemName: kind.symbol)
                    }
                    .tag(kind)
                }
            }
        } label: {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: icebreaker.kind.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DS.Palette.ink)
                    .frame(width: 24)
                Text(icebreaker.kind.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DS.Palette.ink)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(DS.Palette.body)
            }
            .padding(.horizontal, DS.Space.lg)
            .frame(minHeight: 52)
            .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.md).strokeBorder(DS.Palette.ink.opacity(0.35), lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .accessibilityLabel("Format, \(icebreaker.kind.title)")
    }

    // MARK: The card

    private var card: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Label(icebreaker.kind.title, systemImage: icebreaker.kind.symbol)
                    .font(.headline)
                    .foregroundStyle(DS.Palette.lime)
                Text(icebreaker.kind.detail)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.55))
            }
            fields
                .transition(.opacity)
                .id(icebreaker.kind)
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Editor: plain night fill, no contour texture (DESIGN: never on sheets and editors).
        .background(DS.Palette.night, in: .rect(cornerRadius: DS.Radius.xl))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.xl)
                .strokeBorder(DS.Palette.blockEdge, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .animation(Motion.snappy, value: icebreaker.kind)
    }

    @ViewBuilder
    private var fields: some View {
        switch icebreaker {
        case let .twoTruths(statements, lie):
            VStack(spacing: DS.Space.sm) {
                ForEach(0..<3, id: \.self) { i in
                    row(placeholder: [L("I've run 3 marathons"), L("I can do a muscle-up"), L("I've never missed a Sunday run")][i],
                        text: Binding(get: { statements[i] }, set: { v in
                            var st = statements; st[i] = v; icebreaker = .twoTruths(statements: st, lieIndex: lie)
                        }),
                        tag: L("Lie"), tagOn: lie == i) {
                        icebreaker = .twoTruths(statements: statements, lieIndex: i)
                    }
                }
            }
        case let .joke(setup, punchline):
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                bigField(L("Why did the runner bring a map?"), text: Binding(get: { setup }, set: { icebreaker = .joke(setup: $0, punchline: punchline) }))
                field(L("Punchline, hidden until they tap"), text: Binding(get: { punchline }, set: { icebreaker = .joke(setup: setup, punchline: $0) }),
                      accent: true)
            }
        case let .hotTake(text):
            bigField(L("Stretching is overrated."), text: Binding(get: { text }, set: { icebreaker = .hotTake($0) }))
        case let .thisOrThat(q, options, pick):
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                bigField(L("Weekend long run:"), text: Binding(get: { q }, set: { icebreaker = .thisOrThat(question: $0, options: options, pick: pick) }))
                HStack(spacing: DS.Space.sm) {
                    ForEach(0..<2, id: \.self) { i in
                        VStack(spacing: DS.Space.xs) {
                            field([L("Sunrise"), L("Sunset")][i], text: Binding(get: { options[i] }, set: { v in
                                var o = options; o[i] = v; icebreaker = .thisOrThat(question: q, options: o, pick: pick)
                            }), centered: true)
                            tag(L("My pick"), on: pick == i) { icebreaker = .thisOrThat(question: q, options: options, pick: i) }
                        }
                    }
                }
            }
        case let .guess(q, options, answer):
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                bigField(L("My marathon best is…"), text: Binding(get: { q }, set: { icebreaker = .guess(question: $0, options: options, answer: answer) }))
                ForEach(0..<3, id: \.self) { i in
                    row(placeholder: ["3:15", "3:45", "4:20"][i],
                        text: Binding(get: { options[i] }, set: { v in
                            var o = options; o[i] = v; icebreaker = .guess(question: q, options: o, answer: answer)
                        }),
                        tag: L("Right"), tagOn: answer == i) {
                        icebreaker = .guess(question: q, options: options, answer: i)
                    }
                }
            }
        }
    }

    // MARK: In-card controls (styled like the card they'll see)

    /// The headline line of a format: large, like the card's display text.
    private func bigField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.35)), axis: .vertical)
            .lineLimit(1...4)
            .font(.displayBold(24, relativeTo: .title2))
            .foregroundStyle(.white)
            .tint(DS.Palette.lime)
            .revealsOnFocus()
            .padding(.vertical, DS.Space.xs)
    }

    private func field(_ placeholder: String, text: Binding<String>, accent: Bool = false, centered: Bool = false) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.35)), axis: .vertical)
            .lineLimit(1...3)
            .font(.body.weight(.semibold))
            .multilineTextAlignment(centered ? .center : .leading)
            .foregroundStyle(accent ? DS.Palette.lime : .white)
            .tint(DS.Palette.lime)
            .revealsOnFocus()
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, 13)
            .background(.white.opacity(0.08), in: .rect(cornerRadius: DS.Radius.lg))
    }

    private func row(placeholder: String, text: Binding<String>, tag label: String, tagOn: Bool,
                     action: @escaping () -> Void) -> some View {
        HStack(spacing: DS.Space.sm) {
            TextField("", text: text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.35)), axis: .vertical)
                .lineLimit(1...3)
                .font(.body.weight(.medium))
                .foregroundStyle(.white)
                .tint(DS.Palette.lime)
                .revealsOnFocus()
            tag(label, on: tagOn, action: action)
        }
        .padding(.leading, DS.Space.md)
        .padding(.trailing, DS.Space.xs)
        .padding(.vertical, DS.Space.xs)
        .background(tagOn ? DS.Palette.selectedOnNight : .white.opacity(0.08), in: .rect(cornerRadius: DS.Radius.lg))
    }

    private func tag(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            withAnimation(Motion.snappy) { action() }
        } label: {
            Text(label)
                .font(.caption.weight(.heavy))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, DS.Space.md)
                .frame(minHeight: 32)
                .foregroundStyle(on ? DS.Palette.onLime : .white.opacity(0.6))
                .background(on ? DS.Palette.lime : .white.opacity(0.08), in: .capsule)
                .frame(minHeight: 44)
        }
        .buttonStyle(PressScaleStyle(scale: 0.94))
        .accessibilityLabel("Mark as \(Localization.shared.language == .de ? label : label.lowercased(with: .app))")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

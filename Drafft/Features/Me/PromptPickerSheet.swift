import SwiftUI

/// Searchable, categorised prompt library. Questions already on your profile are left out.
struct PromptPickerSheet: View {
    let current: String?
    let used: Set<String>
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var category: String?
    @State private var query = ""
    /// Tapping a row only selects it; the pinned button confirms. Scrolling never picks anything.
    @State private var selection: String?

    private var categories: [PromptCategory] {
        ProfilePrompt.library.filter { category == nil || $0.id == category }
    }

    /// Questions already on your profile are left out (except the one being changed).
    private func matches(_ q: String) -> Bool {
        (!used.contains(q) || q == current) && (query.isEmpty || ProfilePrompt.text(for: q).localizedCaseInsensitiveContains(query))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Space.sm) {
                            chip(L("All"), icon: "widget", on: category == nil) { category = nil }
                            ForEach(ProfilePrompt.library) { c in
                                chip(c.name, icon: c.icon, on: category == c.id) { category = c.id }
                            }
                        }
                        .padding(.horizontal, DS.Space.lg)
                    }
                    .scrollClipDisabled()

                    ForEach(categories) { c in
                        let list = c.questions.filter(matches)
                        if !list.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                Label(c.name, image: c.icon)
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(DS.Palette.ink)
                                    .padding(.vertical, DS.Space.md)
                                ForEach(Array(list.enumerated()), id: \.element) { i, q in
                                    row(q)
                                    if i < list.count - 1 {
                                        Rectangle().fill(DS.Palette.hairline).frame(height: 1)
                                    }
                                }
                            }
                            .padding(.horizontal, DS.Space.lg)
                            .padding(.bottom, DS.Space.xs)
                            .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
                            .padding(.horizontal, DS.Space.lg)
                        }
                    }

                    if categories.allSatisfy({ $0.questions.filter(matches).isEmpty }) {
                        // In a white block: no loose text on the sage page.
                        Text("No prompt matches “\(query)”.")
                            .font(.subheadline)
                            .foregroundStyle(DS.Palette.body)
                            .multilineTextAlignment(.center)
                            .padding(DS.Space.lg)
                            .frame(maxWidth: .infinity, minHeight: 120)
                            .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
                            .padding(.horizontal, DS.Space.lg)
                    }
                }
                .padding(.vertical, DS.Space.sm)
                .animation(Motion.snappy, value: category)
            }
            .background(DS.Palette.canvasSoft)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search prompts")
            .navigationTitle("Pick a prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", image: .icon("close")) { dismiss() }
                }
            }
            .blurredNavigationEdge()
            .bottomBar { footer }
        }
        .presentationDragIndicator(.visible)
        .onAppear { selection = current }
    }

    private func row(_ q: String) -> some View {
        let isSelected = q == selection
        return HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
            // Laid out at its bold width either way: selecting never re-wraps the line or
            // changes the row's height (a question that needs two lines in bold has two lines
            // unselected too). Never truncated.
            ZStack(alignment: .topLeading) {
                Text(ProfilePrompt.text(for: q)).font(.body.weight(.bold)).hidden()
                Text(ProfilePrompt.text(for: q)).font(.body.weight(.medium))
            }
            .foregroundStyle(DS.Palette.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.Space.sm)
            // Centred on the first line, whatever the state.
            CheckDisc(isOn: isSelected)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
        }
        .padding(.vertical, DS.Space.md)
        .contentShape(.rect)
        // A tap gesture (not a Button) so a drag always scrolls the list instead of selecting.
        .onTapGesture {
            Haptics.select()
            // No animation: the weight switches at once (the disc animates on its own).
            selection = q
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var footer: some View {
        VStack(spacing: DS.Space.sm) {
            Button {
                guard let selection else { return }
                Haptics.success()
                onPick(selection)
                dismiss()
            } label: {
                Text("Use this prompt")
            }
            .buttonStyle(.drafftPrimary)
            .disabled(selection == nil || selection == current)
            .draftTrail(RoundedRectangle(cornerRadius: DS.Radius.xl), step: CGSize(width: -6, height: 0))
            .padding(.leading, 12)
            Text(selection.map { $0 == current ? L("That's your current prompt.") : L("“\(ProfilePrompt.text(for: $0))”") } ?? L("Tap a prompt to select it."))
                .font(.footnote)
                .foregroundStyle(DS.Palette.body)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.top, DS.Space.md)
        .padding(.bottom, DS.Space.sm)
    }

    private func chip(_ title: String, icon: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            action()
        } label: {
            Label(title, image: icon)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, DS.Space.md)
                .frame(minHeight: 36)
                .foregroundStyle(on ? DS.Palette.onLime : DS.Palette.ink)
                .background(on ? AnyShapeStyle(DS.Palette.lime) : AnyShapeStyle(DS.Palette.canvas), in: .capsule)
                .frame(minHeight: 44)
        }
        .buttonStyle(PressScaleStyle(scale: 0.94))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

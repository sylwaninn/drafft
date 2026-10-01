import SwiftUI

/// Lifestyle answers (rhythm, food, drinking, smoking). Nothing is picked for the person, each
/// question is optional, and tapping the selected chip clears it. Used in sign-up and Edit profile.
struct LifestylePicker: View {
    @Binding var vitals: Vitals
    /// Picks gendered labels ("Viandarde").
    var gender: DiscoverFilters.Audience?
    /// Unselected chip fill (sage on a white block).
    var chipFill: Surface = DS.Palette.canvasSoft

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            group(L("Early bird or night owl?"), ["Very early bird", "Early bird", "Night owl"], \.chronotype)
            group(L("How you eat"), ["Omnivore", "Meat lover", "Flexitarian", "Vegetarian", "Vegan", "Pescatarian"], \.diet)
            group(L("Drinking"), ["Never", "Rarely", "Socially", "Post-race only", "Apéro is sacred"], \.drinks)
            group(L("Smoking"), ["Never", "Sometimes", "Yes"], \.smokes)
        }
    }

    /// `options` are the stored answers (English); chips show them translated.
    private func group(_ title: String, _ options: [String], _ key: WritableKeyPath<Vitals, String>) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(DS.Palette.ink)
            FlowLayout(spacing: DS.Space.sm) {
                ForEach(options, id: \.self) { o in
                    let on = vitals[keyPath: key] == o
                    Button {
                        Haptics.select()
                        withAnimation(Motion.select) { vitals[keyPath: key] = on ? "" : o }
                    } label: {
                        Text(Vitals.label(for: o, gender: gender))
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, DS.Space.md)
                            .frame(minHeight: 36)
                            .foregroundStyle(on ? DS.Palette.onLime : DS.Palette.ink)
                            .background(on ? AnyShapeStyle(DS.Palette.lime) : AnyShapeStyle(chipFill), in: .capsule)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.94))
                    .accessibilityLabel("\(title) \(Vitals.label(for: o, gender: gender))")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}

extension Vitals {
    /// At least one lifestyle answer given.
    var hasLifestyle: Bool { ![chronotype, diet, drinks, smokes].allSatisfy(\.isEmpty) }
}

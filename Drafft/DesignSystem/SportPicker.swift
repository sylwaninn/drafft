import SwiftUI

/// The one sport picker: a search field over the full catalog, then chips in a fixed order.
/// A limit greys out the rest once reached.
struct SportPicker: View {
    let selected: [Sport]
    var limit: Int?
    var chipBackground: Surface = DS.Palette.canvas
    /// When set, only the first sports of the catalog (plus any picked one) show until "All sports"
    /// is tapped or a search is typed. Keeps a sheet light to open and short to scan.
    var collapsedCount: Int?
    let onToggle: (Sport) -> Void

    @State private var query = ""
    @State private var expanded = false
    @FocusState private var searchFocused: Bool

    private var isCollapsed: Bool {
        collapsedCount != nil && !expanded && query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var results: [Sport] {
        // Catalog order, always: picking a sport never moves the chips around.
        guard isCollapsed, let n = collapsedCount else { return Sport.allCases.filter { $0.matches(query) } }
        return Sport.allCases.enumerated().filter { $0.offset < n || selected.contains($0.element) }.map(\.element)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.sm) {
                Image("magnifier").foregroundStyle(DS.Palette.body)
                TextField("Search \(Sport.allCases.count) sports", text: $query)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image("close-circle")
                            .foregroundStyle(DS.Palette.mute)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .font(.body)
            .padding(.leading, DS.Space.md)
            .padding(.trailing, query.isEmpty ? DS.Space.md : 0)
            .frame(minHeight: 44)
            // The whole capsule focuses the field, icon and padding included.
            .contentShape(.capsule)
            .onTapGesture { searchFocused = true }
            .background(DS.Palette.ink.opacity(0.06), in: .capsule)
            // Inside a FocusScrollView (sign-up, Edit profile, Filters) it scrolls clear of the keyboard.
            .revealsOnFocus(searchFocused)

            if results.isEmpty {
                Text("No sport called “\(query)”. Try another word.")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.body)
            } else {
                FlowLayout(spacing: DS.Space.sm) {
                    ForEach(results) { s in
                        let on = selected.contains(s)
                        let full = limit.map { selected.count >= $0 } ?? false
                        Button {
                            Haptics.select()
                            // A colour change, not a layout change: quick ease, no spring.
                            withAnimation(Motion.select) { onToggle(s) }
                        } label: {
                            SportChip(sport: s, selected: on, fill: chipBackground)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(PressScaleStyle(scale: 0.95))
                        .disabled(!on && full)
                        .opacity(!on && full ? 0.4 : 1)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                    if isCollapsed {
                        Button {
                            Haptics.tap()
                            expanded = true
                        } label: {
                            HStack(spacing: DS.Space.xs + 2) {
                                Text("All \(Sport.allCases.count) sports")
                                Image("alt-arrow-down").font(.caption.weight(.bold))
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DS.Palette.accentInk)
                            .padding(.horizontal, DS.Space.md)
                            .padding(.vertical, DS.Space.sm)
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                        }
                        .buttonStyle(PressScaleStyle(scale: 0.95))
                    }
                }
            }
        }
    }
}

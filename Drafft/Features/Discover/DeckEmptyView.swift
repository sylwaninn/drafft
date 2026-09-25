import SwiftUI

/// Discover when the stack runs out, filtered or not: one screen, words only. What happened, in plain
/// terms and with the real radius, then the two things that help, named by what they do. No picture,
/// no icon over a centred headline: a left-aligned block at the top, like the rest of the app.
struct DeckEmptyView: View {
    let onChats: () -> Void
    let onFilters: () -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Text(app.filters.anyDistance ? L("Any distance") : L("Within \(app.filters.distanceShort)"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DS.Palette.mute)
                Text("No one new for now.")
                    .font(.display(28, relativeTo: .title))
                    .foregroundStyle(DS.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(app.filters.anyDistance
                     ? L("You've seen every profile that matches your filters. Come back later or change them.")
                     : L("You've seen every profile within \(app.filters.distanceShort). Widen it to see more."))
                    .font(.body)
                    .foregroundStyle(DS.Palette.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.Space.xl)

            Divider().padding(.leading, DS.Space.xl)
            if let next = nextRadius {
                row(next >= DiscoverFilters.anyDistance ? L("Widen to any distance") : L("Widen to \(L("\(Int(next)) km"))"),
                    accent: true) {
                    Haptics.success()
                    withAnimation(Motion.snappy) { app.filters.maxDistanceKm = next }
                }
            } else {
                row(L("Adjust filters"), accent: true, action: onFilters)
            }
            Divider().padding(.leading, DS.Space.xl)
            row(L("Go to chats"), accent: false, action: onChats)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
        .padding(.top, DS.Space.sm)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func row(_ title: String, accent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DS.Space.md)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(DS.Palette.mute)
            }
            .foregroundStyle(accent ? DS.Palette.accentInk : DS.Palette.ink)
            .padding(.horizontal, DS.Space.xl)
            .frame(minHeight: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// The next step out: 25 km, 50 km, then any distance. Nil once already at any distance.
    private var nextRadius: Double? {
        [25, 50, DiscoverFilters.anyDistance].first { $0 > app.filters.maxDistanceKm }
    }
}

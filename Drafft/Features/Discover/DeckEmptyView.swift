import SwiftUI

/// Discover when the stack runs out, filtered or not: one screen, the message in the middle. It shows
/// once the last profile card you swiped has flown off (DiscoverView swaps the deck for this after
/// the card's flight), so the icon drafts straight into the spot it left, its two ghosts tucking in
/// behind it like the app icon; then the words rise. The actions sit at the bottom: widen the
/// radius (the move that brings new people), or go to the chats.
struct DeckEmptyView: View {
    let onChats: () -> Void
    let onFilters: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var iconIn = false
    @State private var textIn = false

    private let disc: CGFloat = 72

    var body: some View {
        VStack(spacing: DS.Space.xl) {
            Spacer(minLength: 0)
            VStack(spacing: DS.Space.xl) {
                icon
                message
            }
            Spacer(minLength: 0)
            actions
        }
        .padding(.bottom, DS.Space.lg)
        .onAppear(perform: appear)
    }

    // MARK: Icon

    private var icon: some View {
        ZStack {
            // Two ghosts behind, then the lead: they arrive one after the other.
            ForEach((0..<3).reversed(), id: \.self) { i in
                Circle()
                    .fill(DS.Palette.lime)
                    .frame(width: disc, height: disc)
                    .overlay {
                        if i == 0 {
                            Image(systemName: "binoculars.fill")
                                .font(.system(size: disc * 0.36, weight: .bold))
                                .foregroundStyle(DS.Palette.onLime)
                        }
                    }
                    .opacity(iconIn ? [1, 0.45, 0.2][i] : 0)
                    .offset(x: iconIn ? -CGFloat(i) * 12 : -30)
                    .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.9)
                        .delay(0.05 + Double(i) * 0.07), value: iconIn)
            }
        }
        .frame(width: disc + 24, height: disc)
        .offset(x: 12) // the ghosts reach left: keep the lead on the centre line
        .accessibilityHidden(true)
    }

    // MARK: Message

    private var message: some View {
        VStack(spacing: DS.Space.sm) {
            Text("No one new for now.")
                .font(.display(28, relativeTo: .title))
                .foregroundStyle(DS.Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text(app.filters.anyDistance
                 ? L("You've seen every profile that matches your filters. Come back later or change them.")
                 : L("You've seen every profile within \(app.filters.distanceShort). Widen it to see more."))
                .font(.body)
                .foregroundStyle(DS.Palette.body)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, DS.Space.lg)
        .opacity(textIn ? 1 : 0)
        .offset(y: textIn ? 0 : 10)
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: DS.Space.xs) {
            if let next = nextRadius {
                Button {
                    Haptics.success()
                    withAnimation(Motion.snappy) { app.filters.maxDistanceKm = next }
                } label: {
                    Text(next >= DiscoverFilters.anyDistance ? L("Widen to any distance") : L("Widen to \(L("\(Int(next)) km"))"))
                }
                .buttonStyle(.drafftPrimary)
                link(L("Go to chats"), action: onChats)
            } else {
                Button("Go to chats", action: onChats)
                    .buttonStyle(.drafftPrimary)
                link(L("Adjust filters"), action: onFilters)
            }
        }
    }

    private func link(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DS.Palette.accentInk)
            .buttonStyle(.textLink(fullWidth: true))
    }

    /// The next step out: 25 km, 50 km, then any distance. Nil once already at any distance.
    private var nextRadius: Double? {
        [25, 50, DiscoverFilters.anyDistance].first { $0 > app.filters.maxDistanceKm }
    }

    // MARK: Entrance

    private func appear() {
        guard !reduceMotion else {
            iconIn = true; textIn = true
            return
        }
        iconIn = false; textIn = false
        iconIn = true // each disc carries its own delayed spring
        withAnimation(.easeOut(duration: 0.5).delay(0.45)) { textIn = true }
    }
}

import SwiftUI

/// Discover when the stack runs out, filtered or not: one screen, the message in the middle. It shows
/// the moment the last profile card is swiped: three athlete photos are dealt into the spot it
/// leaves and fan out; then the words rise. The actions sit at the bottom: widen the
/// radius (the move that brings new people), or go to the chats.
struct DeckEmptyView: View {
    /// True when the last card was just swiped: the entrance plays. Coming back to Discover later
    /// (another tab, the app reopened) shows the screen already in place.
    let animate: Bool
    let onChats: () -> Void
    let onFilters: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fanIn = false
    @State private var textIn = false
    /// Picked once per showing.
    @State private var photos: [String] = []

    var body: some View {
        VStack(spacing: DS.Space.xl) {
            Spacer(minLength: 0)
            VStack(spacing: DS.Space.xl) {
                fan
                message
            }
            Spacer(minLength: 0)
            actions
        }
        .padding(.bottom, DS.Space.lg)
        .onAppear(perform: appear)
    }

    // MARK: Fan

    /// Three athletes from the pack photos, the people you're looking for (per your filters), in
    /// the boost sheet's fan: same card sizes, angles and shadow. After the last swipe they are
    /// dealt in quickly, one after the other. A new pile whenever the filters change.
    private var fan: some View {
        let angles: [Double] = [-14, 14, 0]
        let xs: [CGFloat] = [-78, 78, 0]
        let ys: [CGFloat] = [8, 8, -4]
        return ZStack {
            ForEach(Array(photos.enumerated()), id: \.element) { index, name in
                // The last photo leads in the middle; a pile of two keeps the left slot only.
                let i = index == photos.count - 1 ? 2 : index
                let lead = i == 2
                Photo(name: name, side: lead ? 108 : 84)
                    .frame(width: lead ? 108 : 84, height: lead ? 144 : 112)
                    .clipShape(.rect(cornerRadius: DS.Radius.lg))
                    .shadow(color: .black.opacity(lead ? 0.4 : 0), radius: 18, y: 10)
                    .rotationEffect(.degrees(fanIn ? angles[i] : 0), anchor: .bottom)
                    .offset(x: fanIn ? xs[i] : 0, y: fanIn ? ys[i] : -40)
                    .scaleEffect(fanIn ? 1 : 0.7)
                    .opacity(fanIn ? 1 : 0)
                    .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.72)
                        .delay(Double(index) * 0.07), value: fanIn)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .frame(height: 170)
        .accessibilityHidden(true)
        .onAppear { if photos.isEmpty { photos = PackPhotos.pick(for: app.filters.audience) } }
        .onChange(of: app.filters) {
            withAnimation(reduceMotion ? nil : Motion.bouncy) { photos = PackPhotos.pick(for: app.filters.audience) }
        }
    }

    // MARK: Message

    private var message: some View {
        VStack(spacing: DS.Space.sm) {
            Text("No one new for now.")
                .font(.display(22, relativeTo: .title2))
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
                .buttonStyle(.drafftPrimaryFit)
                link(L("Go to chats"), action: onChats)
            } else {
                Button("Go to chats", action: onChats)
                    .buttonStyle(.drafftPrimaryFit)
                link(L("Adjust filters"), action: onFilters)
            }
        }
    }

    private func link(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DS.Palette.accentInk)
            .buttonStyle(.textLink(fullWidth: false))
    }

    /// The next step out: 25 km, 50 km, then any distance. Nil once already at any distance.
    private var nextRadius: Double? {
        [25, 50, DiscoverFilters.anyDistance].first { $0 > app.filters.maxDistanceKm }
    }

    // MARK: Entrance

    private func appear() {
        guard animate, !reduceMotion else {
            var t = Transaction(animation: nil)
            t.disablesAnimations = true
            withTransaction(t) { fanIn = true; textIn = true }
            return
        }
        fanIn = false; textIn = false
        // Quickly after the last card flies off: each photo carries its own delayed spring.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { fanIn = true }
        withAnimation(.easeOut(duration: 0.4).delay(0.35)) { textIn = true }
    }
}

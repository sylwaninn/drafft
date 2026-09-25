import SwiftUI

/// Discover when the stack runs out, filtered or not: one screen. A running track, you in the
/// infield with your radius: a runner laps the lane as it appears (you've been round everyone),
/// then one tap widens the radius, the move that actually brings new people. Text and actions sit
/// in the white block under it.
struct DeckEmptyView: View {
    let onChats: () -> Void
    let onFilters: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lap: CGFloat = 0

    var body: some View {
        VStack(spacing: DS.Space.lg) {
            track
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
            panel
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.lg)
        .onAppear {
            guard !reduceMotion else { lap = 1; return }
            lap = 0
            withAnimation(.easeInOut(duration: 1.6).delay(0.2)) { lap = 1 }
        }
    }

    // MARK: Track

    private var track: some View {
        GeometryReader { g in
            let width = min(g.size.width, 340)
            let height = min(g.size.height, width * 1.35)
            ZStack {
                // Three lanes, the outer one is yours.
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .strokeBorder(DS.Palette.ink.opacity(i == 0 ? 0.16 : 0.08), lineWidth: 1.5)
                        .padding(CGFloat(i) * 18)
                }
                LapLine(progress: lap)
                    .padding(-1)
                // You, in the infield, with the radius you've covered.
                VStack(spacing: DS.Space.sm) {
                    Avatar(name: app.me.portrait, size: 76, ring: true)
                    Label(app.filters.distanceShort, systemImage: "location.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(DS.Palette.ink)
                        .padding(.horizontal, DS.Space.md)
                        .padding(.vertical, DS.Space.xs + 2)
                        .background(DS.Palette.canvas, in: .capsule)
                }
            }
            .frame(width: width, height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Panel

    private var panel: some View {
        VStack(spacing: DS.Space.md) {
            Text("Lap complete.")
                .font(.display(30, relativeTo: .title))
                .foregroundStyle(DS.Palette.ink)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(app.filters.anyDistance ? L("You've seen everyone for now.")
                 : L("You've seen everyone within \(app.filters.distanceShort)."))
                .font(.body)
                .foregroundStyle(DS.Palette.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, DS.Space.sm)

            if let next = nextRadius {
                Button {
                    Haptics.success()
                    withAnimation(Motion.snappy) { app.filters.maxDistanceKm = next }
                } label: {
                    Label(next >= DiscoverFilters.anyDistance ? L("Widen to any distance") : L("Widen to \(L("\(Int(next)) km"))"),
                          systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.drafftPrimary)
                Button("Go to chats", action: onChats)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.accentInk)
                    .buttonStyle(.textLink(fullWidth: true))
            } else {
                Button("Go to chats", action: onChats)
                    .buttonStyle(.drafftPrimary)
                Button("Adjust filters", action: onFilters)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.accentInk)
                    .buttonStyle(.textLink(fullWidth: true))
            }
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity)
        .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
    }

    /// The next step out: 25 km, 50 km, then any distance. Nil once already at any distance.
    private var nextRadius: Double? {
        [25, 50, DiscoverFilters.anyDistance].first { $0 > app.filters.maxDistanceKm }
    }
}

/// The lap run so far along the outer lane, and the runner at its head.
private struct LapLine: View, Animatable {
    var progress: CGFloat
    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GeometryReader { g in
            let lane = Capsule().path(in: CGRect(origin: .zero, size: g.size))
            let run = lane.trimmedPath(from: 0, to: max(0.001, progress))
            ZStack {
                run.stroke(DS.Palette.lime, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                Circle()
                    .fill(DS.Palette.lime)
                    .overlay(Circle().strokeBorder(DS.Palette.white, lineWidth: 3))
                    .frame(width: 18, height: 18)
                    .position(run.currentPoint ?? .zero)
            }
        }
    }
}

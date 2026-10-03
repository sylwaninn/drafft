import SwiftUI

/// Discover filters. Edits a draft; Discover shows the result (or the too-tight message) once applied.
struct FiltersSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DiscoverFilters

    init(filters: DiscoverFilters) {
        _draft = State(initialValue: filters)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.md) {
                    block("Distance", icon: "map-point",
                          value: draft.distanceLabel) {
                        DistanceSlider(value: $draft.maxDistanceKm)
                    }

                    block("Age", icon: "user-rounded",
                          value: "\(draft.ages.lowerBound)–\(draft.ages.upperBound)\(draft.ages.upperBound == DiscoverFilters.ageBounds.upperBound ? "+" : "")") {
                        RangeSlider(range: $draft.ages, bounds: DiscoverFilters.ageBounds)
                    }

                    block("Show me", icon: "eye") {
                        chips(DiscoverFilters.Audience.allCases.map { (audienceTitle($0), nil) },
                              isOn: { $0 == audienceTitle(draft.audience) }) { label in
                            draft.audience = DiscoverFilters.Audience.allCases.first { audienceTitle($0) == label } ?? .everyone
                        }
                        Text("This never shows on your profile.")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.body)
                    }

                    block("Sports", icon: "running", value: draft.sports.isEmpty ? L("Any") : L("\(draft.sports.count) selected")) {
                        SportPicker(selected: Sport.allCases.filter(draft.sports.contains),
                                    chipBackground: DS.Palette.canvasSoft, collapsedCount: 16) { s in
                            if draft.sports.contains(s) { draft.sports.remove(s) } else { draft.sports.insert(s) }
                        }
                    }

                    block("In common", icon: "link-circle") {
                        Toggle(isOn: $draft.sharedSportsOnly) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Only people who do one of my sports")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(DS.Palette.ink)
                                Text("At least one sport in common with you")
                                    .font(.footnote)
                                    .foregroundStyle(DS.Palette.body)
                            }
                        }
                        .tint(DS.Palette.lime)
                    }
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.vertical, DS.Space.sm)
            }
            .background(DS.Palette.canvasSoft)
            .navigationTitle("Filters")
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
        .trackScreen(.filters)
    }

    private var footer: some View {
        VStack(spacing: DS.Space.sm) {
            Button {
                Haptics.success()
                withAnimation(Motion.bouncy) { app.filters = draft }
                dismiss()
            } label: {
                Text("Apply filters")
            }
            .buttonStyle(.drafftPrimary)

            Button("Clear filters") {
                Haptics.tap()
                withAnimation(Motion.snappy) { draft = draft.cleared() }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DS.Palette.accentInk)
            .buttonStyle(.textLink)
            .disabled(draft == draft.cleared())
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.top, DS.Space.md)
    }

    // MARK: Chrome

    private func block<C: View>(_ title: LocalizedStringKey, icon: String, value: String? = nil,
                                @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            // Title and value share the line while both fit; a long translation puts the value under it.
            AdaptiveRow {
                HStack(spacing: DS.Space.sm) {
                    Image(icon)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(DS.Palette.ink)
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(DS.Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                }
            } trailing: {
                if let value {
                    Text(value)
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(DS.Palette.ink)
                        .rollingDigits(wording: value.wording)
                        .animation(Motion.select, value: value)
                }
            }
            content()
        }
        .padding(DS.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
    }

    private func audienceTitle(_ a: DiscoverFilters.Audience) -> String {
        switch a {
        case .women: L("Women")
        case .men: L("Men")
        case .nonBinary: L("Non-binary people")
        case .everyone: L("Everyone")
        }
    }

    private func chips(_ options: [(label: String, icon: String?)], isOn: @escaping (String) -> Bool,
                       toggle: @escaping (String) -> Void) -> some View {
        FlowLayout(spacing: DS.Space.sm) {
            ForEach(options, id: \.label) { option in
                let on = isOn(option.label)
                Button {
                    Haptics.select()
                    withAnimation(Motion.select) { toggle(option.label) }
                } label: {
                    HStack(spacing: 6) {
                        if let icon = option.icon {
                            Image(icon).font(.footnote.weight(.bold))
                        }
                        Text(option.label).font(.footnote.weight(.semibold))
                    }
                    .padding(.horizontal, DS.Space.md)
                    .frame(minHeight: 36)
                    .foregroundStyle(on ? DS.Palette.onLime : DS.Palette.ink)
                    .background(on ? AnyShapeStyle(DS.Palette.lime) : AnyShapeStyle(DS.Palette.canvasSoft), in: .capsule)
                    .frame(minHeight: 44)
                }
                .buttonStyle(PressScaleStyle(scale: 0.94))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Two-thumb slider for an integer range.
struct RangeSlider: View {
    @Binding var range: ClosedRange<Int>
    let bounds: ClosedRange<Int>
    private let thumb: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width - thumb
            let span = CGFloat(bounds.upperBound - bounds.lowerBound)
            let x = { (v: Int) in CGFloat(v - bounds.lowerBound) / span * width }
            let lo = x(range.lowerBound), hi = x(range.upperBound)

            ZStack(alignment: .leading) {
                Capsule().fill(DS.Palette.ink.opacity(0.1)).frame(height: 6)
                    .padding(.horizontal, thumb / 2)
                Capsule().fill(DS.Palette.lime)
                    .frame(width: max(0, hi - lo), height: 6)
                    .offset(x: lo + thumb / 2)
                knob(at: lo) { dx in
                    let v = value(for: dx, width: width)
                    let new = min(v, range.upperBound - 1)
                    if new != range.lowerBound { Haptics.select(); range = new...range.upperBound }
                }
                .accessibilityLabel("Minimum age")
                .accessibilityValue("\(range.lowerBound)")
                .accessibilityAdjustableAction { dir in
                    let v = range.lowerBound + (dir == .increment ? 1 : -1)
                    if v >= bounds.lowerBound && v < range.upperBound { range = v...range.upperBound }
                }
                knob(at: hi) { dx in
                    let v = value(for: dx, width: width)
                    let new = max(v, range.lowerBound + 1)
                    if new != range.upperBound { Haptics.select(); range = range.lowerBound...new }
                }
                .accessibilityLabel("Maximum age")
                .accessibilityValue("\(range.upperBound)")
                .accessibilityAdjustableAction { dir in
                    let v = range.upperBound + (dir == .increment ? 1 : -1)
                    if v <= bounds.upperBound && v > range.lowerBound { range = range.lowerBound...v }
                }
            }
            .frame(height: 44)
            .coordinateSpace(.named("range"))
        }
        .frame(height: 44)
    }

    private func value(for x: CGFloat, width: CGFloat) -> Int {
        let t = min(1, max(0, x / width))
        return bounds.lowerBound + Int((t * CGFloat(bounds.upperBound - bounds.lowerBound)).rounded())
    }

    private func knob(at x: CGFloat, onDrag: @escaping (CGFloat) -> Void) -> some View {
        Circle()
            .fill(Color.white)
            .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            .frame(width: thumb, height: thumb)
            .frame(width: 44, height: 44)
            .contentShape(.circle)
            .offset(x: x - (44 - thumb) / 2)
            // Horizontal-only and simultaneous, so vertical swipes on the slider still scroll the sheet.
            .simultaneousGesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("range")).onChanged { g in
                guard abs(g.translation.width) >= abs(g.translation.height) else { return }
                onDrag(g.location.x - thumb / 2)
            })
    }
}

/// Single-thumb distance slider, 1 km to "50+" (no limit). Custom so it has no tick marks and snaps cleanly.
struct DistanceSlider: View {
    @Binding var value: Double
    private let thumb: CGFloat = 28
    private let lower = DiscoverFilters.distanceBounds.lowerBound
    private let upper = DiscoverFilters.anyDistance

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                let width = geo.size.width - thumb
                let x = CGFloat((min(value, upper) - lower) / (upper - lower)) * width
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Palette.ink.opacity(0.1)).frame(height: 6)
                        .padding(.horizontal, thumb / 2)
                    Capsule().fill(DS.Palette.lime)
                        .frame(width: max(0, x), height: 6)
                        .offset(x: thumb / 2)
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                        .frame(width: thumb, height: thumb)
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                        .offset(x: x - (44 - thumb) / 2)
                }
                .frame(height: 44)
                .contentShape(.rect)
                // Horizontal-only and simultaneous, so vertical swipes on the slider still scroll the sheet.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { g in
                            guard abs(g.translation.width) >= abs(g.translation.height) else { return }
                            let t = min(1, max(0, (g.location.x - thumb / 2) / width))
                            let new = (lower + Double(t) * (upper - lower)).rounded()
                            if new != value {
                                value = new
                                Haptics.select()
                            }
                        }
                )
            }
            .frame(height: 44)
            HStack {
                Text("1 km")
                Spacer()
                Image("infinite").accessibilityLabel("No limit")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(DS.Palette.mute)
            .padding(.horizontal, 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Maximum distance")
        .accessibilityValue(value >= upper ? "Any distance" : "\(Int(value)) kilometres")
        .accessibilityAdjustableAction { dir in
            value = min(upper, max(lower, value + (dir == .increment ? 1 : -1)))
        }
    }
}

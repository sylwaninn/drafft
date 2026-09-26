import SwiftUI

/// Shared header for top-level tabs. Replaces the system large-title bar, which reserves an empty
/// inline row above the title. The title sits right under the status bar and shrinks as content
/// scrolls. Attach it with `.topBar { }` on the scroll view: content passes under it through the
/// app's progressive blur. An optional search field folds into a button on scroll.
struct TabHeader<Leading: View, Trailing: View>: View {
    /// Scroll distance past the top, in points (0 at rest).
    var offset: CGFloat
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    var search: Binding<String>?
    var searchPrompt = L("Search")

    @State private var searchExpanded = false
    /// Search folded into its button. Changes with hysteresis: the header is a safe-area bar, so
    /// its height feeds back into the scroll insets and a plain threshold would flip-flop.
    @State private var folded = false
    @FocusState private var searchFocused: Bool

    /// 0 at rest → 1 once scrolled 56 pt.
    private var collapse: CGFloat { min(1, max(0, offset / 56)) }
    private var showsSearchField: Bool {
        guard search != nil else { return false }
        return !folded || searchExpanded || searchFocused || !(search?.wrappedValue.isEmpty ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(alignment: .center, spacing: DS.Space.sm) {
                // Fixed height: only the scale changes, so the bar (and the insets) stay put.
                leading
                    .scaleEffect(1 - collapse * 0.32, anchor: .leading)
                    .frame(height: 44, alignment: .leading)
                Spacer(minLength: DS.Space.sm)
                if search != nil && !showsSearchField {
                    Button {
                        Haptics.tap()
                        withAnimation(Motion.snappy) { searchExpanded = true }
                        searchFocused = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(DS.Palette.ink)
                            .frame(width: 40, height: 40)
                            .glassEffect(.regular, in: .circle)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel(searchPrompt)
                    .transition(.scale.combined(with: .opacity))
                }
                trailing
            }

            if let search, showsSearchField {
                // One glass container: the field and its clear button morph into each other, the
                // field giving up the button's width as it appears.
                GlassEffectContainer(spacing: DS.Space.sm) {
                    HStack(spacing: DS.Space.sm) {
                        HStack(spacing: DS.Space.sm) {
                            Image(systemName: "magnifyingglass").foregroundStyle(DS.Palette.body)
                            TextField(searchPrompt, text: search)
                                .focused($searchFocused)
                                .submitLabel(.search)
                                .autocorrectionDisabled()
                        }
                        .font(.body)
                        .padding(.horizontal, DS.Space.md)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        // The whole capsule focuses the field, icon and padding included.
                        .contentShape(.capsule)
                        .onTapGesture { searchFocused = true }
                        // Liquid Glass: it reads over anything scrolling under the header, where a
                        // faint tint vanished.
                        .glassEffect(.regular, in: .capsule)

                        if !search.wrappedValue.isEmpty || searchExpanded {
                            Button {
                                Haptics.tap()
                                withAnimation(Motion.bouncy) {
                                    search.wrappedValue = ""
                                    searchExpanded = false
                                }
                                searchFocused = false
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(DS.Palette.onLime)
                                    .frame(width: 40, height: 40)
                                    .glassEffect(.regular.tint(DS.Palette.lime), in: .circle)
                                    .contentShape(.circle)
                            }
                            .buttonStyle(PressScaleStyle())
                            .accessibilityLabel("Clear search")
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                        }
                    }
                }
                .animation(Motion.bouncy, value: search.wrappedValue.isEmpty)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.top, DS.Space.xs)
        .padding(.bottom, DS.Space.sm)
        .animation(Motion.snappy, value: showsSearchField)
        // The search field no longer folds on scroll: changing the header's height moved the
        // list under the finger (a visible jump when scrolling back up).
    }
}

extension TabHeader where Trailing == EmptyView {
    init(offset: CGFloat, search: Binding<String>? = nil, searchPrompt: String = L("Search"),
         @ViewBuilder leading: () -> Leading) {
        self.offset = offset
        self.leading = leading()
        self.trailing = EmptyView()
        self.search = search
        self.searchPrompt = searchPrompt
    }
}

/// Title text used as a TabHeader leading view. Like the status bar, it turns white over a night
/// block or a photo scrolling under it, and back to ink over the page (`EdgeTone`).
struct TabTitle: View {
    let text: String
    @Environment(\.edgeTone) private var tone

    var body: some View {
        Text(text)
            .font(.display(34, relativeTo: .largeTitle))
            .foregroundStyle(tone.map { AnyShapeStyle($0.ink) } ?? AnyShapeStyle(DS.Palette.ink))
            .lineLimit(1)
            .minimumScaleFactor(0.75) // one-word tab names; never "…" in a longer language
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// Reports how far a scroll view has moved past its top, for TabHeader.
    func trackingScrollOffset(_ offset: Binding<CGFloat>) -> some View {
        // Only the fold range matters (see `collapse`): clamped and rounded, so scrolling
        // further doesn't re-render the page every frame.
        onScrollGeometryChange(for: CGFloat.self) {
            min(56, max(0, ($0.contentOffset.y + $0.contentInsets.top).rounded()))
        } action: { _, y in
            offset.wrappedValue = y
        }
    }
}

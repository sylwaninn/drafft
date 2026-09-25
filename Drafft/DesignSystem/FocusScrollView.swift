import SwiftUI

/// Lets a field bring itself into view when it gets focus, above the keyboard and above any
/// pinned bottom bar (which iOS's own avoidance doesn't account for).
struct FocusScroller: @unchecked Sendable { // only used on the main actor
    let proxy: ScrollViewProxy

    @MainActor
    func reveal(_ id: AnyHashable) {
        Task { @MainActor in
            // Let the keyboard and the bar settle first.
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(Motion.snappy) { proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.3)) }
        }
    }
}

private struct FocusScrollerKey: EnvironmentKey {
    static let defaultValue: FocusScroller? = nil
}

extension EnvironmentValues {
    var focusScroller: FocusScroller? {
        get { self[FocusScrollerKey.self] }
        set { self[FocusScrollerKey.self] = newValue }
    }
}

private struct RevealOnFocus: ViewModifier {
    let focused: Bool
    @Environment(\.focusScroller) private var scroller
    @State private var anchor = UUID()

    func body(content: Content) -> some View {
        content
            .id(anchor)
            .onChange(of: focused) { _, on in if on { scroller?.reveal(anchor) } }
    }
}

/// For fields that don't manage focus themselves.
private struct RevealOnOwnFocus: ViewModifier {
    @FocusState private var focused: Bool
    func body(content: Content) -> some View {
        content.focused($focused).modifier(RevealOnFocus(focused: focused))
    }
}

extension View {
    /// Inside a `FocusScrollView`: when this field gets focus, it scrolls to the upper third,
    /// never flush against the keyboard.
    func revealsOnFocus(_ focused: Bool) -> some View { modifier(RevealOnFocus(focused: focused)) }
    /// Same, for a field with no focus state of its own.
    func revealsOnFocus() -> some View { modifier(RevealOnOwnFocus()) }
}

/// A ScrollView whose fields (DrafftField, or any field with `revealsOnFocus`) scroll themselves
/// into view on focus. The content always ends with a margin, so even the last field keeps
/// room between it and the keyboard.
struct FocusScrollView<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
                    .environment(\.focusScroller, FocusScroller(proxy: proxy))
            }
            .contentMargins(.bottom, DS.Space.xl, for: .scrollContent)
        }
    }
}

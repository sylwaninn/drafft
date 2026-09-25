import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

// MARK: - Progressive blur (the one used everywhere)

/// A real progressive blur: the blur radius itself ramps from 0 to `maxRadius` toward `edge`,
/// with no tint and no colour band. Built on the system's variable-blur backdrop filter, the one
/// iOS uses under its own bars. It's a private filter, looked up by name; if it's ever missing,
/// the view falls back to an evenly faded system blur rather than breaking.
struct ProgressiveBlur: UIViewRepresentable {
    var edge: VerticalEdge
    var maxRadius: CGFloat = 14

    func makeUIView(context: Context) -> VariableBlurView {
        VariableBlurView(maxRadius: maxRadius, blurredAtBottom: edge == .bottom)
    }

    func updateUIView(_ view: VariableBlurView, context: Context) {}
}

final class VariableBlurView: UIVisualEffectView {
    private let maxRadius: CGFloat
    private let ramp: CGImage?
    private var filter: NSObject?

    init(maxRadius: CGFloat, blurredAtBottom: Bool) {
        self.maxRadius = maxRadius
        self.ramp = blurredAtBottom ? Self.bottomRamp : Self.topRamp
        super.init(effect: UIBlurEffect(style: .regular))
        isUserInteractionEnabled = false
        // CAFilter(type: "variableBlur"), resolved at runtime.
        if let cls = NSClassFromString(String("retliFAC".reversed())) as? NSObject.Type,
           let f = cls.perform(NSSelectorFromString(String(":epyThtiWretlif".reversed())), with: "variableBlur")?
               .takeUnretainedValue() as? NSObject {
            f.setValue(maxRadius, forKey: "inputRadius")
            f.setValue(ramp, forKey: "inputMaskImage")
            f.setValue(true, forKey: "inputNormalizeEdges")
            filter = f
        } else {
            // Fallback: plain system blur faded with the same ramp.
            let layer = CALayer()
            layer.contents = ramp
            self.layer.mask = layer
        }
        applyFilter()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// UIKit rebuilds the effect's layers when the view leaves and comes back (navigating away
    /// from a chat, switching tabs), which dropped the filter and left a flat, hard-edged blur.
    /// So the filter and the no-tint setup are re-applied every time that can happen.
    private func applyFilter() {
        guard let filter, let backdrop = subviews.first?.layer else { return }
        if (backdrop.filters as? [NSObject])?.first !== filter { backdrop.filters = [filter] }
        for sub in subviews.dropFirst() where sub.alpha != 0 { sub.alpha = 0 }
        if let scale = window?.screen.scale { backdrop.setValue(scale, forKey: "scale") }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyFilter()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        applyFilter()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.mask?.frame = bounds
        applyFilter()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        applyFilter()
    }

    /// Built once: making a CIContext per view cost ~30 ms each time a bar appeared.
    private static let context = CIContext(options: [.useSoftwareRenderer: false])
    private static let bottomRamp = gradient(blurredAtBottom: true)
    private static let topRamp = gradient(blurredAtBottom: false)

    /// Opaque where the blur is strongest, transparent where it's gone, eased in between.
    private static func gradient(blurredAtBottom: Bool) -> CGImage? {
        let f = CIFilter.smoothLinearGradient()
        f.color0 = CIColor.black
        f.color1 = CIColor.clear
        f.point0 = CGPoint(x: 0, y: blurredAtBottom ? 0 : 100)
        f.point1 = CGPoint(x: 0, y: blurredAtBottom ? 100 : 0)
        guard let image = f.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100)) else { return nil }
        return context.createCGImage(image, from: image.extent)
    }
}

// MARK: - The only ways to pin something to an edge

/// The blur only shows when content actually sits under the bar: at rest (top of a page, or a
/// page shorter than the screen) nothing is blurred. Read from the scroll view these are attached to.
private struct EdgeBlurModifier<Bar: View>: ViewModifier {
    enum Kind { case top, bottom, navigation }
    let kind: Kind
    let bar: Bar
    @State private var covered = false

    func body(content: Content) -> some View {
        switch kind {
        case .bottom:
            content
                .scrollEdgeEffectHidden(true, for: .bottom)
                .onScrollGeometryChange(for: Bool.self) { g in
                    // Content continues below the visible area.
                    g.contentSize.height + g.contentInsets.bottom - (g.contentOffset.y + g.containerSize.height) > 1
                } action: { _, v in withAnimation(.easeOut(duration: 0.2)) { covered = v } }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    bar.background {
                        ProgressiveBlur(edge: .bottom)
                            .padding(.top, -DS.Space.xl)
                            .ignoresSafeArea(edges: .bottom)
                            .opacity(covered ? 1 : 0)
                            .allowsHitTesting(false)
                    }
                }
        case .top:
            content
                .scrollEdgeEffectHidden(true, for: .top)
                .onScrollGeometryChange(for: Bool.self) { g in
                    g.contentOffset.y + g.contentInsets.top > 1
                } action: { _, v in withAnimation(.easeOut(duration: 0.2)) { covered = v } }
                .safeAreaInset(edge: .top, spacing: 0) {
                    bar.background {
                        ProgressiveBlur(edge: .top)
                            .padding(.bottom, -DS.Space.xl)
                            .ignoresSafeArea(edges: .top)
                            .opacity(covered ? 1 : 0)
                            .allowsHitTesting(false)
                    }
                }
        case .navigation:
            content
                .scrollEdgeEffectHidden(true, for: .top)
                .onScrollGeometryChange(for: Bool.self) { g in
                    g.contentOffset.y + g.contentInsets.top > 1
                } action: { _, v in withAnimation(.easeOut(duration: 0.2)) { covered = v } }
                .overlay(alignment: .top) {
                    GeometryReader { g in
                        ProgressiveBlur(edge: .top)
                            .frame(height: g.safeAreaInsets.top + DS.Space.xl)
                            .ignoresSafeArea(edges: .top)
                    }
                    .opacity(covered ? 1 : 0)
                    .allowsHitTesting(false)
                }
        }
    }
}

extension View {
    /// Pins `content` to the bottom (validate buttons, the chat composer, above the keyboard).
    /// Scroll content passes under it through a progressive blur. Never a background colour.
    func bottomBar<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        modifier(EdgeBlurModifier(kind: .bottom, bar: content()))
    }

    /// Pins a custom header (TabHeader, step headers) to the top, with the same blur under it.
    func topBar<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        modifier(EdgeBlurModifier(kind: .top, bar: content()))
    }

    /// For screens with the system navigation bar: the same blur under the status bar and the
    /// whole bar (title, avatar, buttons), fading out just below it.
    func blurredNavigationEdge() -> some View {
        modifier(EdgeBlurModifier(kind: .navigation, bar: EmptyView()))
    }
}

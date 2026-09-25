import SwiftUI
import UIKit

// MARK: - Edge tone (the status bar's trick, for headers)

/// Whether what scrolls under a top bar is light or dark. The status bar flips its time and
/// icons the same way: dark ink over a light page or white block, white over a night block or a
/// photo. `topBar` samples it and hands it to the bar through the environment.
enum EdgeTone: Equatable {
    case light, dark

    /// Header text over this tone. Fixed values, not `ink`: in dark mode the page is dark too,
    /// so the rule is the same, light text over dark content, dark text over light content.
    var ink: Color { self == .dark ? .white : Color(uiColor: UIColor(red: 0.055, green: 0.059, blue: 0.047, alpha: 1)) }
}

extension EnvironmentValues {
    /// What sits under the top bar right now; nil at rest (nothing under it: the page's own ink).
    @Entry var edgeTone: EdgeTone?
}

/// Reads the luminance of the scroll content under the top bar, a few times a second while it
/// moves: the content layers are drawn into a tiny bitmap (32 × 8), over the page tone, and
/// averaged. Hysteresis keeps it from flickering on a mid-grey.
struct EdgeToneSampler: UIViewRepresentable {
    let onChange: (EdgeTone) -> Void

    func makeUIView(context: Context) -> SamplerView {
        let view = SamplerView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: SamplerView, context: Context) { view.onChange = onChange }

    final class SamplerView: UIView {
        var onChange: ((EdgeTone) -> Void)?
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var scheduled = false
        private var tone = EdgeTone.light

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isHidden = true
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { observation = nil; return }
            // Attached next to the scroll view: the nearest one around it is the page.
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        private func attach() {
            guard scrollView == nil, let found = nearestScrollView() else { return }
            scrollView = found
            observation = found.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.schedule() }
            }
            schedule()
        }

        private func nearestScrollView() -> UIScrollView? {
            var node: UIView? = superview
            for _ in 0..<8 {
                guard let current = node else { return nil }
                if let hit = Self.firstScrollView(in: current) { return hit }
                node = current.superview
            }
            return nil
        }

        private static func firstScrollView(in view: UIView) -> UIScrollView? {
            var queue = [view]
            while !queue.isEmpty {
                let next = queue.removeFirst()
                if let scroll = next as? UIScrollView, !(scroll is UITextView) { return scroll }
                queue.append(contentsOf: next.subviews)
            }
            return nil
        }

        /// At most every 80 ms while scrolling, plus once when it stops.
        private func schedule() {
            guard !scheduled else { return }
            scheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.scheduled = false
                self?.sample()
            }
        }

        private func sample() {
            guard let scroll = scrollView, let window = scroll.window else { return }
            // The band under the bar: from the status bar down to where the content starts at rest.
            let bottom = scroll.bounds.minY + scroll.adjustedContentInset.top
            let top = scroll.convert(CGPoint(x: 0, y: window.safeAreaInsets.top), from: nil).y
            guard bottom - top > 4 else { return }
            // The title's side (leading 70 %), where the text sits.
            let band = CGRect(x: scroll.bounds.minX, y: top, width: scroll.bounds.width * 0.7, height: bottom - top)
            guard let luminance = Self.luminance(of: scroll.layer, in: band,
                                                 page: UIColor(DS.Palette.sage).resolvedColor(with: traitCollection))
            else { return }
            let next: EdgeTone = luminance < 0.42 ? .dark : luminance > 0.55 ? .light : tone
            guard next != tone else { return }
            tone = next
            onChange?(next)
        }

        private static func luminance(of layer: CALayer, in rect: CGRect, page: UIColor) -> Double? {
            let width = 32, height = 8
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return false }
                // Flip to UIKit's coordinates, then map the band onto the bitmap.
                context.translateBy(x: 0, y: CGFloat(height))
                context.scaleBy(x: CGFloat(width) / rect.width, y: -CGFloat(height) / rect.height)
                context.translateBy(x: -rect.minX, y: -rect.minY)
                context.setFillColor(page.cgColor)
                context.fill(rect)
                layer.render(in: context)
                return true
            }
            guard drawn else { return nil }
            var total = 0.0
            for i in stride(from: 0, to: pixels.count, by: 4) {
                total += 0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])
            }
            return total / Double(width * height) / 255
        }
    }
}

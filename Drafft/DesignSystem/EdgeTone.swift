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

/// Reads what is on screen under the header, the way the status bar does: a tiny snapshot
/// (32 × 8) of the window's band just below the status bar, averaged. The scroll view pokes it
/// (`poke()`, from `onScrollGeometryChange`), at most a dozen times a second; hysteresis keeps a
/// mid-grey from flickering.
@MainActor
final class EdgeToneProbe {
    fileprivate weak var anchor: UIView?
    var onChange: ((EdgeTone) -> Void)?
    private var tone = EdgeTone.light
    private var scheduled = false

    /// The header's text band: from the status bar down this far.
    private let bandHeight: CGFloat = 56

    func poke() {
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.scheduled = false
            self?.sample()
        }
    }

    private func sample() {
        guard let window = anchor?.window, let luminance = luminance(in: window) else { return }
        let next: EdgeTone = luminance < 0.42 ? .dark : luminance > 0.55 ? .light : tone
        guard next != tone else { return }
        tone = next
        onChange?(next)
    }

    private func luminance(in window: UIWindow) -> Double? {
        let band = CGRect(x: 0, y: window.safeAreaInsets.top, width: window.bounds.width * 0.7, height: bandHeight)
        let size = CGSize(width: 32, height: 8)
        let sx = size.width / band.width, sy = size.height / band.height
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        // 8-bit sRGB: on these screens the renderer defaults to 16-bit float (wide colour).
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            // The whole window, scaled so the band lands on the bitmap: what's really on screen.
            window.drawHierarchy(in: CGRect(x: -band.minX * sx, y: -band.minY * sy,
                                            width: window.bounds.width * sx, height: window.bounds.height * sy),
                                 afterScreenUpdates: false)
        }
        guard let cg = image.cgImage, let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
        let step = cg.bitsPerPixel / 8
        guard step >= 3 else { return nil }
        var total = 0.0
        for y in 0..<cg.height {
            for x in 0..<cg.width {
                let p = y * cg.bytesPerRow + x * step
                total += (Double(bytes[p]) + Double(bytes[p + 1]) + Double(bytes[p + 2])) / 3
            }
        }
        return total / Double(cg.width * cg.height) / 255
    }
}

/// Anchors the probe in the page's window.
struct EdgeToneAnchor: UIViewRepresentable {
    let probe: EdgeToneProbe

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        probe.anchor = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) { probe.anchor = view }
}

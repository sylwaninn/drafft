import CoreGraphics

/// Which copy of a server photo a frame needs, like a web page's `srcset`. The media Worker serves each
/// photo at a few widths (`ladder`, its WIDTHS in cloudflare/media-worker, made once and kept next to the
/// original) and the original (2048 px on its long edge) above them.
///
/// - The width a frame needs depends on the photo's proportions: filling a tall card with a 4:5 photo
///   takes the card's height times 0.8, a landscape photo much more. Unknown proportions count as square
///   (never blurry, sometimes larger than needed).
/// - The smallest copy at least that wide is the one to download; a larger one already on this phone
///   stands in for it (`candidates`, best first).
/// - The copy is decoded at the frame's size in pixels (`decodeSize`), not the downloaded copy's: memory
///   holds what the screen shows, whatever was downloaded.
enum Renditions {
    /// Widths the media Worker serves; any other is the original.
    static let ladder = [160, 320, 640, 1_080, 1_440]
    /// A step up the ladder is worth more than a 5 % upscale nobody sees.
    static let tolerance: CGFloat = 0.95
    /// On a limited connection, the width asked of a full copy: a step lighter (1 080 for a 1 344 card).
    static let limitedShare: CGFloat = 0.75
    /// The widest copy a deck card, a grid or any photo but an open profile's asks for: 1 080, about 2.4
    /// pixels a point on a 3x phone's card, which a photo doesn't show (Instagram's order of magnitude for a
    /// full-width photo), for about 40 % less to download and to keep in memory than 1 440. An open profile's
    /// photos (`detail`), looked at closely, may take 1 440 and the original.
    static let everydayWidth: CGFloat = 1_080

    /// The width to ask for: what the frame needs, at most `everydayWidth` unless it's an open profile's photo.
    static func asked(_ needed: CGFloat, detail: Bool) -> CGFloat {
        detail ? needed : min(needed, everydayWidth)
    }

    /// Source pixels wide enough to fill `pixels` (aspect fill) with a photo `aspect` wide for 1 high.
    static func neededWidth(for pixels: CGSize, aspect: CGFloat?) -> CGFloat {
        guard let aspect, aspect.isFinite, aspect > 0 else { return max(pixels.width, pixels.height) }
        return max(pixels.width, pixels.height * aspect)
    }

    /// The smallest rendition covering `width`, nil for the original.
    static func width(covering width: CGFloat) -> Int? {
        ladder.first { CGFloat($0) >= width * tolerance }
    }

    /// Every copy that can be shown for `width`, best first: the rendition covering it, the larger ones,
    /// then the original (nil).
    static func candidates(covering width: CGFloat) -> [Int?] {
        guard let start = Renditions.width(covering: width) else { return [nil] }
        return ladder.filter { $0 >= start }.map(Optional.some) + [nil]
    }

    /// A small copy shown first on a slow connection, sharpened when the right one arrives: a quarter of
    /// the width needed, at least 160 px.
    static func previewWidth(covering width: CGFloat) -> Int {
        Renditions.width(covering: max(160, width / 4)) ?? ladder[ladder.count - 1]
    }

    /// The decoded size: the frame in pixels, its width rounded up to 64 px so frames a few points apart
    /// share one copy in memory, its height following the frame's exact proportions. Every copy of a photo
    /// in one frame (small, sharp) is cropped alike, so a sharper one lands exactly over the last.
    static func decodeSize(for pixels: CGSize) -> CGSize {
        let width = max(64, (pixels.width / 64).rounded(.up) * 64)
        guard pixels.width > 0, pixels.height > 0 else { return CGSize(width: width, height: width) }
        return CGSize(width: width, height: (width * pixels.height / pixels.width).rounded())
    }
}

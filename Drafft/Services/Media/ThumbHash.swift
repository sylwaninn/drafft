import CoreGraphics
import Foundation

/// ThumbHash encoder and decoder (https://evanw.github.io/thumbhash/), ported from the reference implementation.
/// ~25 bytes per image, stored with each photo: the app draws a blurred preview from it instantly,
/// before a single byte of the real image has arrived.
enum ThumbHash {
    /// Base64 hash of an image, downscaled to fit 100×100 first (the encoder's limit).
    static func base64(for image: CGImage) -> String? {
        let scale = min(1, 100 / Double(max(image.width, image.height)))
        let w = max(1, Int((Double(image.width) * scale).rounded()))
        let h = max(1, Int((Double(image.height) * scale).rounded()))
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        return Data(encode(width: w, height: h, rgba: rgba)).base64EncodedString()
    }

    /// Straight port of `rgbaToThumbHash`. Photos are opaque, so premultiplied input is equivalent.
    static func encode(width w: Int, height h: Int, rgba: [UInt8]) -> [UInt8] {
        precondition(w <= 100 && h <= 100 && rgba.count == w * h * 4)
        let count = w * h

        // Average color.
        var avgR = 0.0, avgG = 0.0, avgB = 0.0, avgA = 0.0
        for i in 0..<count {
            let j = i * 4
            let alpha = Double(rgba[j + 3]) / 255
            avgR += alpha / 255 * Double(rgba[j])
            avgG += alpha / 255 * Double(rgba[j + 1])
            avgB += alpha / 255 * Double(rgba[j + 2])
            avgA += alpha
        }
        if avgA > 0 {
            avgR /= avgA
            avgG /= avgA
            avgB /= avgA
        }

        let hasAlpha = avgA < Double(count)
        let lLimit = hasAlpha ? 5.0 : 7.0 // Fewer luminance bits when there's alpha.
        let longest = Double(max(w, h))
        let lx = max(1, Int((lLimit * Double(w) / longest).rounded()))
        let ly = max(1, Int((lLimit * Double(h) / longest).rounded()))

        // RGBA to LPQA, composited atop the average color.
        var l = [Double](repeating: 0, count: count)
        var p = l, q = l, a = l
        for i in 0..<count {
            let j = i * 4
            let alpha = Double(rgba[j + 3]) / 255
            let r = avgR * (1 - alpha) + alpha / 255 * Double(rgba[j])
            let g = avgG * (1 - alpha) + alpha / 255 * Double(rgba[j + 1])
            let b = avgB * (1 - alpha) + alpha / 255 * Double(rgba[j + 2])
            l[i] = (r + g + b) / 3
            p[i] = (r + g) / 2 - b
            q[i] = r - g
            a[i] = alpha
        }

        // DCT: one constant (DC) term and normalized varying (AC) terms per channel.
        func encodeChannel(_ channel: [Double], _ nx: Int, _ ny: Int) -> (dc: Double, ac: [Double], scale: Double) {
            var dc = 0.0, scale = 0.0
            var ac: [Double] = []
            var fx = [Double](repeating: 0, count: w)
            for cy in 0..<ny {
                var cx = 0
                while cx * ny < nx * (ny - cy) {
                    var f = 0.0
                    for x in 0..<w { fx[x] = cos(.pi / Double(w) * Double(cx) * (Double(x) + 0.5)) }
                    for y in 0..<h {
                        let fy = cos(.pi / Double(h) * Double(cy) * (Double(y) + 0.5))
                        for x in 0..<w { f += channel[x + y * w] * fx[x] * fy }
                    }
                    f /= Double(count)
                    if cx > 0 || cy > 0 {
                        ac.append(f)
                        scale = max(scale, abs(f))
                    } else {
                        dc = f
                    }
                    cx += 1
                }
            }
            if scale > 0 { ac = ac.map { 0.5 + 0.5 / scale * $0 } }
            return (dc, ac, scale)
        }

        let lc = encodeChannel(l, max(3, lx), max(3, ly))
        let pc = encodeChannel(p, 3, 3)
        let qc = encodeChannel(q, 3, 3)
        let ac = hasAlpha ? encodeChannel(a, 5, 5) : nil

        // Header.
        let isLandscape = w > h
        let header24 = Int((63 * lc.dc).rounded())
            | (Int((31.5 + 31.5 * pc.dc).rounded()) << 6)
            | (Int((31.5 + 31.5 * qc.dc).rounded()) << 12)
            | (Int((31 * lc.scale).rounded()) << 18)
            | ((hasAlpha ? 1 : 0) << 23)
        let header16 = (isLandscape ? ly : lx)
            | (Int((63 * pc.scale).rounded()) << 3)
            | (Int((63 * qc.scale).rounded()) << 9)
            | ((isLandscape ? 1 : 0) << 15)
        var hash: [UInt8] = [
            UInt8(header24 & 255), UInt8((header24 >> 8) & 255), UInt8(header24 >> 16),
            UInt8(header16 & 255), UInt8(header16 >> 8)
        ]
        if let ac { hash.append(UInt8(Int((15 * ac.dc).rounded()) | (Int((15 * ac.scale).rounded()) << 4))) }

        // Varying factors, two per byte.
        let acStart = hasAlpha ? 6 : 5
        var acIndex = 0
        let channels = hasAlpha ? [lc.ac, pc.ac, qc.ac, ac?.ac ?? []] : [lc.ac, pc.ac, qc.ac]
        for channel in channels {
            for f in channel {
                let byte = acStart + (acIndex >> 1)
                if byte >= hash.count { hash.append(0) }
                hash[byte] |= UInt8(Int((15 * f).rounded()) << ((acIndex & 1) << 2))
                acIndex += 1
            }
        }
        return hash
    }

    // MARK: Decoding

    /// The preview a hash stands for: at most 32 × 32 px, the photo's approximate aspect ratio.
    /// Nil for a hash that isn't one (too short, bad base64).
    static func image(fromBase64 string: String) -> CGImage? {
        guard let data = Data(base64Encoded: string), let decoded = decode([UInt8](data)) else { return nil }
        let provider = CGDataProvider(data: Data(decoded.rgba) as CFData)
        return provider.flatMap {
            CGImage(width: decoded.width, height: decoded.height, bitsPerComponent: 8, bitsPerPixel: 32,
                    bytesPerRow: decoded.width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                    provider: $0, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        }
    }

    /// Width over height, from the header alone.
    static func approximateAspectRatio(_ hash: [UInt8]) -> Double? {
        guard hash.count >= 5 else { return nil }
        let header = Int(hash[3])
        let hasAlpha = hash[2] & 0x80 != 0
        let isLandscape = hash[4] & 0x80 != 0
        let lx = isLandscape ? (hasAlpha ? 5 : 7) : header & 7
        let ly = isLandscape ? header & 7 : (hasAlpha ? 5 : 7)
        guard lx > 0, ly > 0 else { return nil }
        return Double(lx) / Double(ly)
    }

    // Kept in one piece like the reference, so it can be compared line by line.
    // swiftlint:disable cyclomatic_complexity function_body_length
    /// Straight port of `thumbHashToRGBA` (straight, not premultiplied, alpha).
    static func decode(_ hash: [UInt8]) -> (width: Int, height: Int, rgba: [UInt8])? {
        guard hash.count >= 5, let ratio = approximateAspectRatio(hash) else { return nil }
        let header24 = Int(hash[0]) | (Int(hash[1]) << 8) | (Int(hash[2]) << 16)
        let header16 = Int(hash[3]) | (Int(hash[4]) << 8)
        let lDC = Double(header24 & 63) / 63
        let pDC = Double((header24 >> 6) & 63) / 31.5 - 1
        let qDC = Double((header24 >> 12) & 63) / 31.5 - 1
        let lScale = Double((header24 >> 18) & 31) / 31
        let hasAlpha = (header24 >> 23) != 0
        let pScale = Double((header16 >> 3) & 63) / 63
        let qScale = Double((header16 >> 9) & 63) / 63
        let isLandscape = (header16 >> 15) != 0
        let lx = max(3, isLandscape ? (hasAlpha ? 5 : 7) : header16 & 7)
        let ly = max(3, isLandscape ? header16 & 7 : (hasAlpha ? 5 : 7))
        guard !hasAlpha || hash.count >= 6 else { return nil }
        let aDC = hasAlpha ? Double(hash[5] & 15) / 15 : 1
        let aScale = hasAlpha ? Double(hash[5] >> 4) / 15 : 0

        // Varying factors, two per byte (saturation boosted 1.25× against quantisation).
        let acStart = hasAlpha ? 6 : 5
        var acIndex = 0
        var truncated = false
        func decodeChannel(_ nx: Int, _ ny: Int, _ scale: Double) -> [Double] {
            var ac: [Double] = []
            for cy in 0..<ny {
                var cx = cy > 0 ? 0 : 1
                while cx * ny < nx * (ny - cy) {
                    let byte = acStart + (acIndex >> 1)
                    guard byte < hash.count else { truncated = true; return ac }
                    let nibble = (Int(hash[byte]) >> ((acIndex & 1) << 2)) & 15
                    ac.append((Double(nibble) / 7.5 - 1) * scale)
                    acIndex += 1
                    cx += 1
                }
            }
            return ac
        }
        let lAC = decodeChannel(lx, ly, lScale)
        let pAC = decodeChannel(3, 3, pScale * 1.25)
        let qAC = decodeChannel(3, 3, qScale * 1.25)
        let aAC = hasAlpha ? decodeChannel(5, 5, aScale) : []
        guard !truncated else { return nil }

        let w = Int((ratio > 1 ? 32 : 32 * ratio).rounded())
        let h = Int((ratio > 1 ? 32 / ratio : 32).rounded())
        guard w > 0, h > 0 else { return nil }
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let nx = max(lx, hasAlpha ? 5 : 3), ny = max(ly, hasAlpha ? 5 : 3)
        var fx = [Double](repeating: 0, count: nx), fy = [Double](repeating: 0, count: ny)
        func byte(_ v: Double) -> UInt8 { UInt8(max(0, 255 * min(1, v))) }
        var i = 0
        for y in 0..<h {
            for cy in 0..<ny { fy[cy] = cos(.pi / Double(h) * (Double(y) + 0.5) * Double(cy)) }
            for x in 0..<w {
                var l = lDC, p = pDC, q = qDC, a = aDC
                for cx in 0..<nx { fx[cx] = cos(.pi / Double(w) * (Double(x) + 0.5) * Double(cx)) }

                var j = 0
                for cy in 0..<ly {
                    var cx = cy > 0 ? 0 : 1
                    let fy2 = fy[cy] * 2
                    while cx * ly < lx * (ly - cy) {
                        l += lAC[j] * fx[cx] * fy2
                        cx += 1; j += 1
                    }
                }
                j = 0
                for cy in 0..<3 {
                    var cx = cy > 0 ? 0 : 1
                    let fy2 = fy[cy] * 2
                    while cx < 3 - cy {
                        let f = fx[cx] * fy2
                        p += pAC[j] * f
                        q += qAC[j] * f
                        cx += 1; j += 1
                    }
                }
                if hasAlpha {
                    j = 0
                    for cy in 0..<5 {
                        var cx = cy > 0 ? 0 : 1
                        let fy2 = fy[cy] * 2
                        while cx < 5 - cy {
                            a += aAC[j] * fx[cx] * fy2
                            cx += 1; j += 1
                        }
                    }
                }

                let b = l - 2 / 3 * p
                let r = (3 * l - b + q) / 2
                let g = r - q
                rgba[i] = byte(r); rgba[i + 1] = byte(g); rgba[i + 2] = byte(b); rgba[i + 3] = byte(a)
                i += 4
            }
        }
        return (w, h, rgba)
    }    // swiftlint:enable cyclomatic_complexity function_body_length
}

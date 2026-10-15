import CoreGraphics
import SwiftUI

// Metal surfaces, made from the finish's own token colours (no images): brushed grain with a bright
// band for Gold, Rose Gold and Titanium; soft satin highlights for Silver; fine powder-coat grain for
// Graphite. Used only where metal helps: primary buttons, the add button, the finish discs.

enum MetalTexture {
    private static var cache: [String: CGImage] = [:]

    /// A tile, 512 × 128 px (256 × 64 pt), the band running across the middle.
    static func image(_ t: Tokens) -> CGImage? {
        let key = "\(t.appearance.rawValue)-\(t.finish.rawValue)"
        if let c = cache[key] { return c }
        let w = 512, h = 128
        var px = [UInt8](repeating: 255, count: w * h * 4)
        var seed: UInt32 = 0x2545F491 &+ UInt32(t.finish.rawValue.count * 7919)
        func rnd() -> Double { seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5; return Double(seed % 10_000) / 10_000 }
        let lo = t.accentLow, mid = t.accent, hi = t.accentHigh
        func mix(_ a: RGB, _ b: RGB, _ k: Double) -> (Double, Double, Double) {
            (a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k)
        }
        // Brushed: each row has its own brightness (the grain), drifting slowly along the row.
        var rowGrain = (0..<h).map { _ in rnd() - 0.5 }
        for i in 1..<h { rowGrain[i] = rowGrain[i] * 0.6 + rowGrain[i - 1] * 0.4 }
        let streak = (0..<w).map { _ in rnd() - 0.5 }
        for y in 0..<h {
            let v = Double(y) / Double(h - 1)
            for x in 0..<w {
                let u = Double(x) / Double(w - 1)
                var c: (Double, Double, Double)
                switch t.finish {
                case .silver:
                    // Satin: soft light falling from the top left and pooling bottom right.
                    let l1 = exp(-(pow(u - 0.25, 2) + pow(v - 0.2, 2)) / 0.08)
                    let l2 = exp(-(pow(u - 0.8, 2) + pow(v - 0.75, 2)) / 0.12) * 0.7
                    let base = mix(lo, mid, 0.55 + 0.45 * v * 0.3)
                    let k = min(1, l1 + l2)
                    c = (base.0 + (hi.r - base.0) * k, base.1 + (hi.g - base.1) * k, base.2 + (hi.b - base.2) * k)
                case .graphite:
                    // Powder coat: an even tone with a fine, random grain.
                    let g = (rnd() - 0.5) * 0.06
                    let base = mix(lo, mid, 0.65 + 0.2 * (1 - v))
                    c = (base.0 + g, base.1 + g, base.2 + g)
                default:
                    // Brushed: a bright band through the middle, darker towards the edges, horizontal grain.
                    let band = exp(-pow(v - 0.5, 2) / 0.012)
                    let body = 0.35 + 0.65 * (1 - abs(v - 0.5) * 2)
                    let base = mix(lo, mid, body)
                    let g = rowGrain[y] * 0.06 + streak[(x + y * 37) % w] * 0.015
                    c = (base.0 + (hi.r - base.0) * band + g, base.1 + (hi.g - base.1) * band + g, base.2 + (hi.b - base.2) * band + g)
                }
                let o = (y * w + x) * 4
                px[o] = UInt8(max(0, min(1, c.0)) * 255); px[o + 1] = UInt8(max(0, min(1, c.1)) * 255); px[o + 2] = UInt8(max(0, min(1, c.2)) * 255)
            }
        }
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let img = ctx.makeImage() else { return nil }
        cache[key] = img
        return img
    }

    /// The texture as a fill (falls back to the plain gradient).
    static func paint(_ t: Tokens) -> AnyShapeStyle {
        guard let img = image(t) else { return AnyShapeStyle(t.metal) }
        return AnyShapeStyle(ImagePaint(image: Image(decorative: img, scale: 2), scale: 1))
    }
}

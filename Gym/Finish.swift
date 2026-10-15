import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

// The materials: real metal (a gradient from shadow to highlight, never one flat colour), a fine
// film grain behind dark themes, and colours toned down from neon to jewel tones.

extension Palette {
    /// Gold and silver as metal: shadow → base → highlight → base → shadow.
    static let goldMetal: [Color] = [0x7A5A22, 0xB8913F, 0xE8CF8A, 0xF7EBC4, 0xC9A55C, 0x8F6B2B].map { Color(hex: $0) }
    static let silverMetal: [Color] = [0x5C6168, 0x9DA3AB, 0xD9DDE2, 0xF6F7F9, 0xB3B8BF, 0x6B7077].map { Color(hex: $0) }

    static let roseGoldMetal: [Color] = [0x7E4A3E, 0xB7796A, 0xE3B2A1, 0xF6DCD0, 0xC98F7E, 0x8C5546].map { Color(hex: $0) }
    static let titaniumMetal: [Color] = [0x4A5058, 0x7F8893, 0xB8C0C9, 0xE4E8EC, 0x96A0AB, 0x535A63].map { Color(hex: $0) }
    static let bronzeMetal: [Color] = [0x5E3B1C, 0x9A6332, 0xC9935A, 0xE8C49A, 0xAD7740, 0x6B4320].map { Color(hex: $0) }

    var metalStops: [Color]? {
        switch name {
        case "noir": return Palette.goldMetal
        case "sterling": return Palette.silverMetal
        case "roseGold": return Palette.roseGoldMetal
        case "titanium": return Palette.titaniumMetal
        case "bronze": return Palette.bronzeMetal
        default: return nil
        }
    }

    /// Fill for accent buttons and pills: brushed metal on the metal themes, the accent elsewhere.
    var accentFill: AnyShapeStyle {
        if let m = metalStops { return AnyShapeStyle(LinearGradient(colors: m, startPoint: .topLeading, endPoint: .bottomTrailing)) }
        return AnyShapeStyle(accent)
    }

    /// Big titles: engraved metal on the metal themes.
    var titleStyle: AnyShapeStyle {
        if let m = metalStops { return AnyShapeStyle(LinearGradient(colors: [m[3], m[2], m[1]], startPoint: .top, endPoint: .bottom)) }
        return AnyShapeStyle(Color.primary)
    }

    /// Toned down from neon: less saturation, no glaring brightness. Neon keeps its glow on purpose.
    func refined() -> Palette {
        guard name != "neon", !matte else { return self }
        var p = self
        let s = scheme == .dark ? 0.74 : 0.86, b = scheme == .dark ? 0.88 : 1.0
        p.accent = accent.toned(saturation: s, maxBrightness: b)
        p.calories = calories.toned(saturation: s, maxBrightness: b)
        p.protein = protein.toned(saturation: s, maxBrightness: b)
        p.fat = fat.toned(saturation: s, maxBrightness: b)
        p.carbs = carbs.toned(saturation: s, maxBrightness: b)
        p.good = good.toned(saturation: s, maxBrightness: b)
        p.warn = warn.toned(saturation: s, maxBrightness: b)
        return p
    }
}

extension Color {
    /// The same hue with saturation scaled and brightness capped.
    func toned(saturation k: Double, maxBrightness cap: Double) -> Color {
        let r = resolve(in: EnvironmentValues())
        let R = Double(r.red), G = Double(r.green), B = Double(r.blue)
        let mx = max(R, G, B), mn = min(R, G, B), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == R { h = ((G - B) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == G { h = (B - R) / d + 2 }
            else { h = (R - G) / d + 4 }
            h /= 6; if h < 0 { h += 1 }
        }
        let s = mx == 0 ? 0 : d / mx
        return Color(hue: h, saturation: s * k, brightness: min(mx, cap), opacity: Double(r.opacity))
    }
}

/// Film grain: fine monochrome noise, made once, tiled. Barely visible, but it stops dark
/// surfaces looking like flat plastic.
struct Grain: View {
    var opacity = 0.05
    private static let tile: CGImage? = {
        let n = 160
        var px = [UInt8](repeating: 0, count: n * n * 4)
        var seed: UInt32 = 0x9E3779B9
        for i in 0..<(n * n) {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5     // xorshift: same grain every launch
            let v = UInt8(truncatingIfNeeded: seed)
            px[i * 4] = v; px[i * 4 + 1] = v; px[i * 4 + 2] = v; px[i * 4 + 3] = 255
        }
        guard let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        return ctx.makeImage()
    }()

    var body: some View {
        if let t = Grain.tile {
            Image(decorative: t, scale: 2).resizable(resizingMode: .tile)
                .opacity(opacity).blendMode(.overlay).allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

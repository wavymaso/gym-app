import SwiftUI

// The theme system: Appearance (Automatic, Light, Dark, Black) × Finish (Titanium, Silver,
// Graphite, Gold, Rose Gold). Every colour in the app comes from here.
//
// Rules: neutrals are a tonal ramp with the faintest tint of the finish; the accent is the finish
// (a desaturated metal), used sparingly; macro and semantic colours are muted so they sit inside the
// metal palette and stay apart for colour-blind eyes (terracotta / ochre / slate blue differ in hue
// AND lightness). Elevation comes from tone + a hairline, not shadows.

enum Appearance: String, CaseIterable, Identifiable {
    case automatic, light, dark, black
    var id: String { rawValue }
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    /// What it looks like right now (Automatic follows the system).
    func resolved(systemDark: Bool) -> Appearance { self == .automatic ? (systemDark ? .dark : .light) : self }
}

enum Finish: String, CaseIterable, Identifiable {
    case titanium, silver, graphite, gold, roseGold
    var id: String { rawValue }
    var label: String { self == .roseGold ? "Rose Gold" : rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// The neutrals' tint: hue, and how much (barely: you shouldn't be able to name the colour).
    fileprivate var tint: (hue: Double, amount: Double) {
        switch self {
        case .titanium: return (212, 1.0)     // cool
        case .silver: return (220, 0.6)       // cool, lighter touch
        case .graphite: return (0, 0)         // true neutral
        case .gold: return (40, 1.0)          // warm
        case .roseGold: return (18, 0.9)      // warm
        }
    }
}

/// A colour as numbers (so contrast can be checked), made into a SwiftUI Color when drawn.
struct RGB: Equatable {
    var r, g, b: Double
    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }

    /// Hue in degrees, saturation and brightness 0…1.
    static func hsb(_ h: Double, _ s: Double, _ v: Double) -> RGB {
        let hh = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let c = v * s, x = c * (1 - abs(hh.truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let (r, g, b): (Double, Double, Double) = switch Int(hh) {
            case 0: (c, x, 0)
            case 1: (x, c, 0)
            case 2: (0, c, x)
            case 3: (0, x, c)
            case 4: (x, 0, c)
            default: (c, 0, x)
        }
        return RGB(r: r + m, g: g + m, b: b + m)
    }

    /// WCAG relative luminance.
    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    func contrast(_ o: RGB) -> Double {
        let a = luminance, b = o.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// Every token for one Appearance × Finish.
struct Tokens: Equatable {
    var appearance: Appearance        // light, dark or black (resolved)
    var finish: Finish
    var isDark: Bool { appearance != .light }

    // Neutrals, back to front
    var background: RGB               // the page
    var grouped: RGB                  // grouped / inset areas
    var card: RGB
    var raised: RGB                   // things on cards: chips, fields, ring tracks
    var separator: RGB
    var text3: RGB                    // tertiary text
    var text2: RGB                    // secondary text, labels, units
    var text1: RGB                    // primary text and key numbers

    // The finish
    var accent: RGB                   // buttons, main ring, selection, key numbers
    var accentHigh: RGB               // the specular highlight (same hue, lighter)
    var accentLow: RGB                // the shade (same hue, darker)
    var onAccent: RGB                 // text on an accent fill

    // Data
    var calories: RGB
    var protein: RGB
    var fat: RGB
    var carbs: RGB

    // Meaning (muted)
    var good: RGB                     // on target
    var over: RGB                     // over target (not red)
    var under: RGB                    // under target
    var record: RGB                   // a PR
    var warning: RGB

    /// The 0.5 pt edge at the top of a card: a touch lighter in the dark, darker in the light.
    var hairline: Color { isDark ? Color.white.opacity(appearance == .black ? 0.10 : 0.075) : Color.black.opacity(0.07) }
    /// The one shadow level, for floating things (sheets, the add button, toasts).
    var floatShadow: (color: Color, radius: CGFloat, y: CGFloat) { (Color.black.opacity(isDark ? 0.45 : 0.14), 18, 8) }

    /// Metal: a 3-stop gradient within the accent's own hue (light from the top left).
    var metal: LinearGradient { LinearGradient(colors: [accentHigh.color, accent.color, accentLow.color], startPoint: .topLeading, endPoint: .bottomTrailing) }

    static func make(_ a: Appearance, _ f: Finish) -> Tokens {
        let ap = a == .automatic ? .dark : a
        let (hue, amt) = f.tint
        // The neutral ramp: brightness steps, a whisper of the finish's hue.
        func n(_ v: Double, _ s: Double) -> RGB { .hsb(hue, s * amt, v) }
        let neutrals: [RGB]
        switch ap {
        case .light:
            neutrals = [n(0.955, 0.012), n(0.975, 0.008), n(1.0, 0.0), n(0.93, 0.014), n(0.86, 0.014), n(0.43, 0.03), n(0.36, 0.035), n(0.09, 0.04)]
        case .black:
            neutrals = [RGB(r: 0, g: 0, b: 0), n(0.045, 0.10), n(0.085, 0.07), n(0.13, 0.06), n(0.20, 0.05), n(0.58, 0.03), n(0.70, 0.025), n(0.95, 0.012)]
        default:
            neutrals = [n(0.075, 0.09), n(0.10, 0.08), n(0.135, 0.065), n(0.18, 0.055), n(0.24, 0.045), n(0.56, 0.03), n(0.69, 0.025), n(0.94, 0.012)]
        }
        let dark = ap != .light

        // The finish's metal: hue, saturation, and brightness in the dark and in the light.
        let accent: (h: Double, s: Double, dark: Double, light: Double) = switch f {
            case .titanium: (210, 0.14, 0.72, 0.42)     // warm grey with a hint of blue
            case .silver: (220, 0.03, 0.88, 0.45)       // bright, nearly neutral
            case .graphite: (30, 0.03, 0.58, 0.26)      // dark gunmetal
            case .gold: (40, 0.36, 0.84, 0.47)          // champagne
            case .roseGold: (16, 0.32, 0.84, 0.50)      // muted copper-pink
        }
        let av = dark ? accent.dark : accent.light
        let acc = RGB.hsb(accent.h, accent.s, av)
        let hi = RGB.hsb(accent.h, accent.s * 0.55, min(1, av + (dark ? 0.13 : 0.16)))
        let lo = RGB.hsb(accent.h, min(1, accent.s * 1.25), av - (dark ? 0.20 : 0.12))
        let on = dark ? neutrals[0].luminance < 0.01 ? RGB.hsb(hue, 0.05 * amt, 0.08) : neutrals[0] : RGB(r: 1, g: 1, b: 1)

        // Data and meaning: muted, separated in hue and lightness (colour-blind safe).
        func d(_ h: Double, _ s: Double, _ vd: Double, _ vl: Double, _ sl: Double? = nil) -> RGB { dark ? .hsb(h, s, vd) : .hsb(h, sl ?? s * 1.15, vl) }
        return Tokens(
            appearance: ap, finish: f,
            background: neutrals[0], grouped: neutrals[1], card: neutrals[2], raised: neutrals[3], separator: neutrals[4],
            text3: neutrals[5], text2: neutrals[6], text1: neutrals[7],
            accent: acc, accentHigh: hi, accentLow: lo, onAccent: on,
            // Calories is the metal itself: brightest in the dark, deepest in the light, so it never
            // blends with a macro of a similar hue. The macros sit in the middle of the tonal range.
            calories: dark ? hi : lo,
            protein: d(10, 0.44, 0.74, 0.60),         // terracotta
            fat: d(42, 0.44, 0.80, 0.64, 0.62),       // ochre
            carbs: d(205, 0.32, 0.72, 0.56),          // slate blue
            good: d(150, 0.26, 0.72, 0.46),           // sage
            over: d(24, 0.46, 0.86, 0.56),            // muted amber-copper
            under: d(205, 0.12, 0.66, 0.48),          // quiet slate
            record: d(44, 0.30, 0.92, 0.55),          // champagne
            warning: d(36, 0.50, 0.88, 0.55)
        )
    }

    // MARK: Checks

    /// Every text/background pair that must pass WCAG AA (4.5, or 3 for large numbers and icons).
    var contrastPairs: [(name: String, ratio: Double, minimum: Double)] {
        var out: [(String, Double, Double)] = []
        for (bn, bg) in [("background", background), ("card", card), ("raised", raised)] {
            out.append(("text1 on \(bn)", text1.contrast(bg), 4.5))
            out.append(("text2 on \(bn)", text2.contrast(bg), 4.5))
            if bn != "raised" { out.append(("text3 on \(bn)", text3.contrast(bg), 4.5)) }
        }
        out.append(("on-accent on accent", onAccent.contrast(accent), 4.5))
        out.append(("accent text on card", accent.contrast(card), 4.5))
        for (mn, m) in [("protein", protein), ("fat", fat), ("carbs", carbs), ("over", over), ("good", good), ("warning", warning)] {
            out.append(("\(mn) on card (large/graphic)", m.contrast(card), 3))
        }
        return out
    }

    static var all: [Tokens] {
        [Appearance.light, .dark, .black].flatMap { a in Finish.allCases.map { make(a, $0) } }
    }
}

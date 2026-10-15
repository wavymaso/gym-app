import Foundation
// Every Appearance × Finish: text passes WCAG AA, macro colours stay apart (also for colour-blind eyes),
// and neutrals are tinted so little you can't name the colour.
var fails = 0
let verbose = CommandLine.arguments.contains("-v")
func check(_ n: String, _ ok: Bool) { if !ok { fails += 1; print("FAIL", n) } }

/// Simulates deuteranopia (the most common colour blindness), Machado 2009 (severity 1).
func deutan(_ c: RGB) -> RGB {
    func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    func gam(_ v: Double) -> Double { let x = min(max(v, 0), 1); return x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055 }
    let r = lin(c.r), g = lin(c.g), b = lin(c.b)
    return RGB(r: gam(0.367322 * r + 0.860646 * g - 0.227968 * b), g: gam(0.280085 * r + 0.672501 * g + 0.047413 * b),
               b: gam(-0.011820 * r + 0.042940 * g + 0.968881 * b))
}
/// Rough perceptual distance (CIE76 in Lab).
func deltaE(_ a: RGB, _ b: RGB) -> Double {
    func lab(_ c: RGB) -> (Double, Double, Double) {
        func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let r = lin(c.r), g = lin(c.g), b = lin(c.b)
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047, y = 0.2126 * r + 0.7152 * g + 0.0722 * b, z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16 / 116 }
        return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
    }
    let p = lab(a), q = lab(b)
    return sqrt(pow(p.0 - q.0, 2) + pow(p.1 - q.1, 2) + pow(p.2 - q.2, 2))
}
func chroma(_ c: RGB) -> Double { let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b); return mx - mn }

for t in Tokens.all {
    let name = "\(t.appearance.rawValue)/\(t.finish.rawValue)"
    for p in t.contrastPairs {
        check("\(name): \(p.name) \(String(format: "%.2f", p.ratio)) < \(p.minimum)", p.ratio >= p.minimum)
        if verbose { print(name, p.name, String(format: "%.2f", p.ratio)) }
    }
    let macros = [("calories", t.calories), ("protein", t.protein), ("fat", t.fat), ("carbs", t.carbs)]
    for i in 0..<macros.count { for j in (i + 1)..<macros.count {
        let a = macros[i], b = macros[j]
        check("\(name): \(a.0) vs \(b.0) too close (ΔE \(Int(deltaE(a.1, b.1))))", deltaE(a.1, b.1) >= 20)
        check("\(name): \(a.0) vs \(b.0) too close for deuteranopia (ΔE \(Int(deltaE(deutan(a.1), deutan(b.1)))))", deltaE(deutan(a.1), deutan(b.1)) >= 12)
    } }
    // Not a highlighter: no data colour at full saturation.
    for m in macros.dropFirst() { check("\(name): \(m.0) too saturated", chroma(m.1) < 0.5) }
    // You can't name the background's colour.
    check("\(name): background tinted too much", chroma(t.background) < 0.02 && chroma(t.card) < 0.02)
}
print(fails == 0 ? "ALL PASSED" : "\(fails) FAILED")

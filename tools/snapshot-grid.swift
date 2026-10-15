import CoreGraphics
import CoreText
import Foundation
import ImageIO
// Lays the theme screenshots out: one row per Finish, one column per screen; one image per
// Appearance (THEME-SNAPSHOTS-light/dark/black.png) plus all three stacked (THEME-SNAPSHOTS.png).
let dir = CommandLine.arguments[1], out = CommandLine.arguments[2]
let appearances = ["light", "dark", "black"], finishes = ["titanium", "silver", "graphite", "gold", "roseGold"]
let screens = ["today", "food", "workout", "weight", "settings"]
let cw = 300, ch = 652, label = 150, gap = 12, head = 44

func load(_ p: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}
func text(_ ctx: CGContext, _ s: String, _ x: Int, _ y: Int, size: CGFloat = 20) {
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    let attr = NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                                          NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.08, alpha: 1)])
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(CTLineCreateWithAttributedString(attr), ctx)
}
func grid(_ rows: [(a: String, f: String)], _ path: String) {
    let W = label + screens.count * (cw + gap) + gap, H = head + rows.count * (ch + gap) + gap
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 0.55, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    for (c, s) in screens.enumerated() { text(ctx, s.capitalized, label + c * (cw + gap) + gap, H - head + 12) }
    for (r, row) in rows.enumerated() {
        let y = H - head - (r + 1) * (ch + gap)
        text(ctx, row.a.capitalized, 12, y + ch / 2 + 12)
        text(ctx, row.f == "roseGold" ? "Rose Gold" : row.f.capitalized, 12, y + ch / 2 - 16)
        for (c, s) in screens.enumerated() {
            if let im = load("\(dir)/\(row.a)-\(row.f)-\(s).png") {
                ctx.draw(im, in: CGRect(x: label + c * (cw + gap) + gap, y: y, width: cw, height: ch))
            }
        }
    }
    let img = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil); CGImageDestinationFinalize(dest)
    print("wrote \(path): \(W)×\(H)")
}
let base = out.replacingOccurrences(of: ".png", with: "")
for a in appearances { grid(finishes.map { (a, $0) }, "\(base)-\(a).png") }
grid(appearances.flatMap { a in finishes.map { (a, $0) } }, out)

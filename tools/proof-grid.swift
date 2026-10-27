import CoreGraphics
import CoreText
import Foundation
import ImageIO
// Before | after, per screen: one image per theme (PROOF-dark-titanium.png …), rows = screens.
let dir = CommandLine.arguments[1]
// <dir> [beforeName] [afterName] [appearance-finish …]
let beforeName = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "before"
let afterName = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "after"
let themes: [(String, String)] = CommandLine.arguments.count > 4
    ? CommandLine.arguments.dropFirst(4).map { let p = $0.split(separator: "-"); return (String(p[0]), String(p[1])) }
    : [("dark", "titanium"), ("light", "titanium"), ("black", "gold")]
let screens = ["today", "food", "plan", "swap", "workout", "weight", "settings"]
let cw = 300, ch = 652, gap = 12, head = 44, pair = 40
func load(_ p: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}
func text(_ ctx: CGContext, _ s: String, _ x: Int, _ y: Int, size: CGFloat = 20) {
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    let attr = NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                                          NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.08, alpha: 1)])
    ctx.textPosition = CGPoint(x: x, y: y); CTLineDraw(CTLineCreateWithAttributedString(attr), ctx)
}
for (a, f) in themes {
    let cols = screens.count, W = gap + cols * (2 * cw + gap + pair), H = head * 2 + ch + gap
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 0.55, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    text(ctx, "\(a.capitalized) · \(f.capitalized): before | after", gap, H - 30, size: 24)
    for (c, s) in screens.enumerated() {
        let x0 = gap + c * (2 * cw + gap + pair)
        text(ctx, s.capitalized, x0, H - head - 30)
        for (k, side) in [beforeName, afterName].enumerated() {
            if let im = load("\(dir)/\(side)/\(a)-\(f)-\(s).png") { ctx.draw(im, in: CGRect(x: x0 + k * (cw + gap), y: gap, width: cw, height: ch)) }
        }
    }
    let path = "PROOF-\(a)-\(f).png"
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
    print("wrote", path)
}

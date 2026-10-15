import AppKit
// Lays the theme screenshots out: one row per Appearance × Finish, one column per screen.
let dir = CommandLine.arguments[1], out = CommandLine.arguments[2]
let appearances = ["light", "dark", "black"], finishes = ["titanium", "silver", "graphite", "gold", "roseGold"]
let screens = ["today", "food", "workout", "weight", "settings"]
let cw = 300.0, ch = 652.0, label = 170.0, gap = 12.0, head = 40.0
let W = label + Double(screens.count) * (cw + gap) + gap, H = head + Double(appearances.count * finishes.count) * (ch + gap) + gap
let img = NSImage(size: NSSize(width: W, height: H))
img.lockFocus()
NSColor(white: 0.5, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: NSColor.black]
for (c, s) in screens.enumerated() {
    NSString(string: s.capitalized).draw(at: NSPoint(x: label + Double(c) * (cw + gap) + gap, y: H - head + 8), withAttributes: attrs)
}
var row = 0
for a in appearances { for f in finishes {
    let y = H - head - Double(row + 1) * (ch + gap)
    NSString(string: "\(a.capitalized)\n\(f == "roseGold" ? "Rose Gold" : f.capitalized)").draw(in: NSRect(x: 12, y: y + ch / 2 - 30, width: label - 20, height: 60), withAttributes: attrs)
    for (c, s) in screens.enumerated() {
        if let im = NSImage(contentsOfFile: "\(dir)/\(a)-\(f)-\(s).png") {
            im.draw(in: NSRect(x: label + Double(c) * (cw + gap) + gap, y: y, width: cw, height: ch))
        }
    }
    row += 1
} }
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out): \(Int(W))×\(Int(H))")

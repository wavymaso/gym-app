// Draws the app icon (1024×1024). Run: swift make-icon.swift <output.png>
import AppKit
import SwiftUI

func c(_ hex: UInt32) -> Color {
    Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
}

struct Arc: View {
    let progress: Double, color: Color, width: CGFloat
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: width)
            Circle().trim(from: 0, to: progress)
                .stroke(AngularGradient(colors: [color.opacity(0.65), color], center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * progress)),
                        style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.6), radius: 18)
        }
    }
}

struct Icon: View {
    var mac = false
    var body: some View {
        if mac {
            // macOS icons: a rounded square inset in the canvas, with a soft shadow.
            art.frame(width: 1024, height: 1024).scaleEffect(824.0 / 1024)
                .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous).inset(by: 100))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
                .frame(width: 1024, height: 1024)
        } else {
            art
        }
    }

    var art: some View {
        ZStack {
            LinearGradient(colors: [c(0x1C2140), c(0x0A0A10)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [c(0x4C7DFF).opacity(0.25), .clear], center: .center, startRadius: 10, endRadius: 520)
            Arc(progress: 0.78, color: c(0x4C7DFF), width: 46).frame(width: 860, height: 860)
            ZStack {
                Lifter().fill(LinearGradient(colors: [.white, c(0xD9E2FF)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: c(0x4C7DFF).opacity(0.9), radius: 30)
                Definition().stroke(c(0x1C2140).opacity(0.55), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 740, height: 740).offset(y: 46)
        }
        .frame(width: 1024, height: 1024)
    }
}

/// A bodybuilder hitting a front double biceps, upper body (drawn in a 100 × 100 box).
struct Lifter: Shape {
    func path(in r: CGRect) -> Path {
        let sx = r.width / 100, sy = r.height / 100
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + x * sx, y: r.minY + y * sy) }
        var path = Path()
        // Head and neck
        path.addEllipse(in: CGRect(origin: p(43, 13), size: CGSize(width: 14 * sx, height: 16 * sy)))
        path.addRect(CGRect(origin: p(45.5, 26), size: CGSize(width: 9 * sx, height: 6 * sy)))
        // Torso: traps, wide lats, narrow waist
        var t = Path()
        t.move(to: p(50, 29))
        t.addQuadCurve(to: p(70, 36), control: p(61, 29))      // right trap
        t.addQuadCurve(to: p(74, 47), control: p(76, 40))      // right delt
        t.addQuadCurve(to: p(62, 84), control: p(72, 68))      // right lat to waist
        t.addLine(to: p(38, 84))
        t.addQuadCurve(to: p(26, 47), control: p(28, 68))      // left lat
        t.addQuadCurve(to: p(30, 36), control: p(24, 40))      // left delt
        t.addQuadCurve(to: p(50, 29), control: p(39, 29))      // left trap
        t.closeSubpath()
        path = path.union(t)
        // Arms, mirrored: triceps hanging under, forearm up, one big biceps peak
        for side in [-1.0, 1.0] {
            func q(_ x: Double, _ y: Double) -> CGPoint { p(50 + side * (x - 50), y) }
            var a = Path()
            a.move(to: q(30, 53))                               // armpit
            a.addQuadCurve(to: q(11, 48), control: q(19, 58))   // triceps
            a.addQuadCurve(to: q(7, 40), control: q(6, 46))     // elbow
            a.addQuadCurve(to: q(11, 15), control: q(4, 27))    // forearm, outside
            a.addLine(to: q(18.5, 15))                          // wrist
            a.addQuadCurve(to: q(17, 35), control: q(20.5, 25)) // forearm, inside
            a.addQuadCurve(to: q(31, 39), control: q(21, 21))   // biceps peak
            a.addQuadCurve(to: q(30, 53), control: q(33, 46))   // into the delt
            a.closeSubpath()
            path = path.union(a)
            let fist = q(14.8, 10.5)
            path = path.union(Path(ellipseIn: CGRect(x: fist.x - 6.2 * sx, y: fist.y - 6 * sy, width: 12.4 * sx, height: 12 * sy)))
        }
        return path
    }
}

/// Pecs, abs and biceps lines, so it reads as muscle.
struct Definition: Shape {
    func path(in r: CGRect) -> Path {
        let sx = r.width / 100, sy = r.height / 100
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + x * sx, y: r.minY + y * sy) }
        var d = Path()
        d.move(to: p(36, 50)); d.addQuadCurve(to: p(50, 51), control: p(42, 56))     // left pec
        d.move(to: p(64, 50)); d.addQuadCurve(to: p(50, 51), control: p(58, 56))     // right pec
        d.move(to: p(50, 41)); d.addLine(to: p(50, 81))                               // linea alba
        for y in [61.0, 69.0, 77.0] {                                                 // abs
            d.move(to: p(43, y)); d.addQuadCurve(to: p(50, y + 0.5), control: p(46.5, y + 2))
            d.move(to: p(57, y)); d.addQuadCurve(to: p(50, y + 0.5), control: p(53.5, y + 2))
        }
        for side in [-1.0, 1.0] {                                                     // elbow crease, delt line
            func q(_ x: Double, _ y: Double) -> CGPoint { p(50 + side * (x - 50), y) }
            d.move(to: q(17, 35)); d.addQuadCurve(to: q(12, 40), control: q(13, 36))
            d.move(to: q(32, 41)); d.addQuadCurve(to: q(32, 51), control: q(29, 46))
        }
        return d
    }
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let mac = CommandLine.arguments.contains("--mac")
MainActor.assumeIsolated {
    let r = ImageRenderer(content: Icon(mac: mac))
    r.scale = 1
    guard let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { exit(1) }
    try! png.write(to: URL(fileURLWithPath: out))
    print("wrote", out, cg.width, cg.height)
}

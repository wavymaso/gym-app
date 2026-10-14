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
            Arc(progress: 0.78, color: c(0x4C7DFF), width: 74).frame(width: 720, height: 720)
            Arc(progress: 0.62, color: c(0xFF4F70), width: 66).frame(width: 540, height: 540)
            Arc(progress: 0.86, color: c(0x2FD39A), width: 58).frame(width: 376, height: 376)
            Image(systemName: "dumbbell.fill").font(.system(size: 170, weight: .bold)).foregroundStyle(.white)
                .rotationEffect(.degrees(-30))
        }
        .frame(width: 1024, height: 1024)
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

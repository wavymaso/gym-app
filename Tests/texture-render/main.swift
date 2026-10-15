import SwiftUI
MainActor.assumeIsolated {
    let v = VStack(spacing: 16) {
        ForEach([Appearance.dark, .light], id: \.self) { a in
            HStack(spacing: 16) {
                ForEach(Finish.allCases) { f in
                    let t = Tokens.make(a, f)
                    VStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 14).fill(MetalTexture.paint(t)).frame(width: 220, height: 54)
                            .overlay(Text("Start workout").font(.system(size: 16, weight: .semibold)).foregroundStyle(t.onAccent.color))
                        HStack(spacing: 14) {
                            Circle().fill(MetalTexture.paint(t)).frame(width: 58, height: 58)
                                .overlay(Image(systemName: "plus").font(.system(size: 22, weight: .bold)).foregroundStyle(t.onAccent.color))
                            Circle().fill(MetalTexture.paint(t)).frame(width: 34, height: 34)
                        }
                        Text("\(a.label) · \(f.label)").font(.system(size: 11)).foregroundStyle(t.text2.color)
                    }
                    .padding(14).background(t.background.color, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }.padding(20).background(Color.gray)
    let r = ImageRenderer(content: v); r.scale = 2
    let img = r.cgImage!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil); CGImageDestinationFinalize(dest)
}

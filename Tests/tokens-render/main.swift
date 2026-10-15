import SwiftUI
// Renders the token gallery to a PNG: Tests/tokens-render/run.sh out.png
MainActor.assumeIsolated {
    let r = ImageRenderer(content: TokenGallery())
    r.scale = 2
    guard let img = r.cgImage else { print("render failed"); exit(1) }
    let url = URL(fileURLWithPath: CommandLine.arguments[1])
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(img.width)×\(img.height)")
}

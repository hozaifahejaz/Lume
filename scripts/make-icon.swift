// Renders Lume's app icon into an .iconset folder at every size macOS asks for.
// Usage: make-icon <output.iconset>
import SwiftUI
import AppKit

func color(_ hex: UInt32, _ opacity: Double = 1) -> Color {
    Color(.sRGB,
          red: Double((hex >> 16) & 0xFF) / 255,
          green: Double((hex >> 8) & 0xFF) / 255,
          blue: Double(hex & 0xFF) / 255,
          opacity: opacity)
}

/// Drawn on Apple's 1024pt icon grid (y down): a pastel squircle with two soft glows,
/// a frosted glass tile and three graphite bars.
struct LumeIcon: View {
    private let body_ = RoundedRectangle(cornerRadius: 186, style: .continuous)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: 1024, height: 1024)

            body_
                .fill(LinearGradient(stops: [.init(color: color(0xD9E8FF), location: 0),
                                             .init(color: color(0xEDE4FF), location: 0.55),
                                             .init(color: color(0xFFE9DC), location: 1)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.22), radius: 14, y: 12)
                .offset(x: 100, y: 100)

            contents
                .frame(width: 824, height: 824)
                .clipShape(body_)
                .offset(x: 100, y: 100)

            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .stroke(Color.white.opacity(0.7), lineWidth: 2)
                .frame(width: 822, height: 822)
                .offset(x: 101, y: 101)
        }
        .frame(width: 1024, height: 1024, alignment: .topLeading)
    }

    /// Everything clipped to the body, in body-local coordinates (canvas minus 100).
    private var contents: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            Circle().fill(color(0x9EC5FF, 0.7)).frame(width: 400, height: 400)
                .blur(radius: 40).position(x: 230, y: 230)
            Circle().fill(color(0xFFC9A8, 0.6)).frame(width: 440, height: 440)
                .blur(radius: 40).position(x: 620, y: 640)

            let tile = RoundedRectangle(cornerRadius: 150, style: .continuous)
            tile.fill(LinearGradient(colors: [Color.white.opacity(0.85), Color.white.opacity(0.45)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(tile.stroke(Color.white.opacity(0.9), lineWidth: 3))
                .frame(width: 560, height: 560)
                .offset(x: 132, y: 132)

            bar(x: 380, y: 430, height: 220)
            bar(x: 486, y: 350, height: 300)
            bar(x: 592, y: 480, height: 170)

            Rectangle()
                .fill(LinearGradient(stops: [.init(color: Color.white.opacity(0.35), location: 0),
                                             .init(color: Color.white.opacity(0), location: 0.35)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
        }
        .frame(width: 824, height: 824, alignment: .topLeading)
    }

    private func bar(x: CGFloat, y: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(LinearGradient(colors: [color(0x4A4A50), color(0x1C1C1E)], startPoint: .top, endPoint: .bottom))
            .frame(width: 52, height: height)
            .offset(x: x - 100, y: y - 100)
    }
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Lume.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let sizes: [(name: String, pixels: Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
    ("512x512", 512), ("512x512@2x", 1024),
]

MainActor.assumeIsolated {
    // One 1024px master, then high-quality downsampling for every smaller size.
    let renderer = ImageRenderer(content: LumeIcon())
    renderer.scale = 1
    guard let master = renderer.cgImage else { fatalError("Could not render the icon") }
    for size in sizes {
        guard let context = CGContext(data: nil, width: size.pixels, height: size.pixels, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
        context.interpolationQuality = .high
        context.draw(master, in: CGRect(x: 0, y: 0, width: size.pixels, height: size.pixels))
        guard let image = context.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            fatalError("Could not render icon at \(size.name)")
        }
        try! png.write(to: output.appendingPathComponent("icon_\(size.name).png"))
    }
}

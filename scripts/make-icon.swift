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

/// Drawn on Apple's 1024pt icon grid: an 824pt light squircle holding three graphite bars,
/// the same mark as the menu bar meter, with a soft glass sheen.
struct LumeIcon: View {
    private let tile = RoundedRectangle(cornerRadius: 186, style: .continuous)
    private let levels: [CGFloat] = [0.55, 0.82, 0.4]

    var body: some View {
        ZStack {
            tile
                .fill(LinearGradient(colors: [color(0xFFFFFF), color(0xF1F2F5), color(0xE3E5EA)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(tile.fill(RadialGradient(colors: [color(0xDCE8FF, 0.45), .clear],
                                                  center: UnitPoint(x: 0.2, y: 0.05),
                                                  startRadius: 0, endRadius: 620)))
                .overlay(tile.strokeBorder(LinearGradient(colors: [Color.white, color(0xC9CCD3, 0.6)],
                                                          startPoint: .top, endPoint: .bottom), lineWidth: 3))
                .frame(width: 824, height: 824)
                .shadow(color: color(0x1C1C1E, 0.18), radius: 18, y: 10)

            HStack(alignment: .bottom, spacing: 64) {
                ForEach(0..<3, id: \.self) { index in
                    bar(levels[index])
                }
            }
            .frame(height: 440, alignment: .bottom)
            .offset(y: 8)

            // A gentle sheen across the upper half, like light on glass.
            tile
                .fill(LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0)],
                                     startPoint: .top, endPoint: .center))
                .frame(width: 824, height: 824)
                .blendMode(.screen)
        }
        .frame(width: 1024, height: 1024)
    }

    private func bar(_ level: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Capsule().fill(color(0x3A3A3C, 0.1))
            Capsule()
                .fill(LinearGradient(colors: [color(0x48484A), color(0x2C2C2E)], startPoint: .top, endPoint: .bottom))
                .frame(height: 440 * level)
                .shadow(color: color(0x000000, 0.18), radius: 6, y: 4)
        }
        .frame(width: 92, height: 440)
    }
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Lume.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let sizes: [(name: String, pixels: CGFloat)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
    ("512x512", 512), ("512x512@2x", 1024),
]

MainActor.assumeIsolated {
    for size in sizes {
        let renderer = ImageRenderer(content: LumeIcon())
        renderer.scale = size.pixels / 1024
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            fatalError("Could not render icon at \(size.name)")
        }
        try! png.write(to: output.appendingPathComponent("icon_\(size.name).png"))
    }
}

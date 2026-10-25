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

/// Drawn on Apple's 1024pt icon grid: an 824pt squircle tile with a glass lens holding three gauge rings.
struct LumeIcon: View {
    private let tile = RoundedRectangle(cornerRadius: 186, style: .continuous)

    var body: some View {
        ZStack {
            tile
                .fill(LinearGradient(colors: [color(0xB9D5FF), color(0xC9C4FF), color(0xE2CFFF)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(tile.fill(RadialGradient(colors: [Color.white.opacity(0.65), .clear],
                                                  center: UnitPoint(x: 0.25, y: 0.1),
                                                  startRadius: 0, endRadius: 640)))
                .overlay(tile.fill(RadialGradient(colors: [color(0xBFF0DE, 0.55), .clear],
                                                  center: UnitPoint(x: 0.85, y: 0.95),
                                                  startRadius: 0, endRadius: 420)))
                .overlay(tile.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.9), Color.white.opacity(0.2)],
                                                          startPoint: .top, endPoint: .bottom), lineWidth: 3))
                .frame(width: 824, height: 824)
                .shadow(color: color(0x1A2550, 0.22), radius: 20, y: 12)

            lens
        }
        .frame(width: 1024, height: 1024)
    }

    private var lens: some View {
        ZStack {
            // Glass body with a soft drop shadow onto the tile.
            Circle()
                .fill(RadialGradient(colors: [Color.white.opacity(0.97), color(0xF1F5FF, 0.92), color(0xD5DFFA, 0.95)],
                                     center: UnitPoint(x: 0.36, y: 0.3), startRadius: 0, endRadius: 340))
                .shadow(color: color(0x2B3A7A, 0.3), radius: 28, y: 20)

            // Inner shadow along the lower rim gives the lens depth.
            Circle()
                .strokeBorder(LinearGradient(colors: [Color.clear, color(0x5C6CA8, 0.35)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 22)
                .blur(radius: 9)
                .clipShape(Circle())

            ring(diameter: 420, fraction: 0.74, hue: color(0x0A84FF))
            ring(diameter: 324, fraction: 0.58, hue: color(0x5E5CE6))
            ring(diameter: 228, fraction: 0.42, hue: color(0x30B0C7))

            // Specular highlight across the top of the glass.
            Ellipse()
                .fill(LinearGradient(colors: [Color.white.opacity(0.85), Color.white.opacity(0)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 400, height: 200)
                .offset(y: -158)

            Circle()
                .strokeBorder(LinearGradient(colors: [Color.white, Color.white.opacity(0.25)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 5)
        }
        .frame(width: 568, height: 568)
    }

    private func ring(diameter: CGFloat, fraction: Double, hue: Color) -> some View {
        ZStack {
            Circle().stroke(hue.opacity(0.13), lineWidth: 34)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(LinearGradient(colors: [hue.opacity(0.7), hue], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 34, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: hue.opacity(0.35), radius: 8, y: 5)
        }
        .frame(width: diameter, height: diameter)
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

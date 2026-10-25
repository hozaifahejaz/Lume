import SwiftUI
import AppKit
import Darwin

/// A thin graphite line with a very faint fill, for a rolling history of values in 0...1.
/// Slots not yet sampled (the leading zeros after launch) are left empty rather than drawn flat.
struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let slots = max(values.count - 1, 1)
            let skipped = values.prefix(while: { $0 == 0 }).count
            let points = values.enumerated().dropFirst(min(skipped, values.count - 1)).map { index, value in
                CGPoint(
                    x: geo.size.width * CGFloat(index) / CGFloat(slots),
                    y: 1 + (geo.size.height - 2) * (1 - CGFloat(min(max(value, 0), 1)))
                )
            }
            ZStack {
                Path { path in
                    guard let first = points.first, let last = points.last else { return }
                    path.move(to: CGPoint(x: first.x, y: geo.size.height))
                    points.forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(Theme.graphite.opacity(0.05))
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(Theme.graphite.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

/// Shows as many rows as fit the available height, so a panel never has to scroll.
struct FittingRows<Item: Identifiable, Row: View>: View {
    let items: [Item]
    let rowHeight: CGFloat
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        GeometryReader { geo in
            let count = max(0, Int(geo.size.height / rowHeight))
            VStack(spacing: 0) {
                ForEach(Array(items.prefix(count))) { item in
                    row(item).frame(height: rowHeight)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Row hover: a quiet wash behind the row.
struct HoverWash: ViewModifier {
    @StateObject private var hover = ViewState(false)

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(hover.value ? 0.04 : 0))
            )
            .contentShape(Rectangle())
            .onHover { hover.value = $0 }
            .animation(.easeOut(duration: 0.15), value: hover.value)
    }
}

extension View {
    func hoverWash() -> some View { modifier(HoverWash()) }
}

/// Finds the app behind a process or a launch agent and caches its icon.
@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func forProcess(_ pid: Int32) -> NSImage? {
        var buffer = [CChar](repeating: 0, count: 4096)
        if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0,
           let image = forPath(String(cString: buffer)) {
            return image
        }
        if let app = NSRunningApplication(processIdentifier: pid), app.bundleURL != nil {
            return app.icon
        }
        return nil
    }

    /// The icon of the outermost .app containing `path`, so helpers show their parent app.
    static func forPath(_ path: String) -> NSImage? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard let index = parts.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        let appPath = parts[...index].joined(separator: "/")
        if let cached = cache[appPath] { return cached }
        guard FileManager.default.fileExists(atPath: appPath) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: appPath)
        cache[appPath] = image
        return image
    }
}

/// The menu bar mark: three concentric arcs echoing the app icon, drawn as a template image.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let rings: [(radius: CGFloat, sweep: CGFloat)] = [(7.4, 280), (4.7, 220)]
            for ring in rings {
                let track = NSBezierPath()
                track.appendArc(withCenter: center, radius: ring.radius, startAngle: 0, endAngle: 360)
                track.lineWidth = 1.6
                NSColor.black.withAlphaComponent(0.3).setStroke()
                track.stroke()

                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: ring.radius, startAngle: 90,
                              endAngle: 90 - ring.sweep, clockwise: true)
                arc.lineWidth = 1.6
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            }
            let dot = NSBezierPath(ovalIn: NSRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4))
            NSColor.black.setFill()
            dot.fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

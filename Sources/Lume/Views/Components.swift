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

    /// Prefers the app path already known from grouping; asks the kernel only when there isn't one.
    static func forProcess(_ pid: Int32, appPath: String? = nil) -> NSImage? {
        if let appPath, let image = forPath(appPath) { return image }
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

/// A neutral symbol for a process with no app: a terminal for things you installed,
/// gears for the system's own daemons, a dashed app for anything else.
enum ProcessSymbol {
    static func forPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if ["/usr/local/", "/opt/homebrew/", home + "/"].contains(where: path.hasPrefix) { return "terminal" }
        if ["/usr/libexec/", "/usr/sbin/", "/System/", "/sbin/", "/usr/bin/"].contains(where: path.hasPrefix) {
            return "gearshape.2"
        }
        return "app.dashed"
    }
}

/// The menu bar mark: three rounded bars — processor, memory, disk — that double as a quiet live meter.
/// Drawn as a template image so macOS tints it for light, dark and highlighted menu bars.
enum MenuBarIcon {
    /// A resting shape for places that don't need live values.
    static let image = make(values: [0.55, 0.8, 0.4])

    static func make(values: [Double]) -> NSImage {
        let barWidth: CGFloat = 2.5, gap: CGFloat = 2, height: CGFloat = 14
        let width = barWidth * 3 + gap * 2
        let canvas = NSSize(width: ceil(width) + 2, height: 18)
        let image = NSImage(size: canvas, flipped: false) { rect in
            // Whole points at the left and bottom keep 2.5pt bars on exact pixels at @2x.
            let originX = floor((rect.width - width) / 2)
            let originY: CGFloat = 2
            for (index, value) in values.prefix(3).enumerated() {
                let x = originX + CGFloat(index) * (barWidth + gap)
                let track = NSRect(x: x, y: originY, width: barWidth, height: height)
                NSColor.black.withAlphaComponent(0.35).setFill()
                NSBezierPath(roundedRect: track, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()

                // Snap the fill to half points so its top edge lands on a pixel.
                let level = (max(barWidth, height * CGFloat(min(max(value, 0), 1))) * 2).rounded() / 2
                let fill = NSRect(x: x, y: originY, width: barWidth, height: level)
                NSColor.black.setFill()
                NSBezierPath(roundedRect: fill, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Lume"
        return image
    }
}

/// Redraws the menu bar meter every 2 seconds, and only when a value has moved by 3% or more.
@MainActor
final class MenuBarMeter: ObservableObject {
    static let showsCPUKey = "menuBarShowsCPU"

    @Published private(set) var image = MenuBarIcon.image
    /// Processor use for the optional text beside the icon, on the same 2-second beat.
    @Published private(set) var cpuText = "0%"
    private var shown: [Double] = []
    private var timer: Timer?

    init(monitor: SystemMonitor) {
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self, weak monitor] _ in
            Task { @MainActor in
                guard let self, let monitor else { return }
                self.update([monitor.cpu, monitor.memory.fraction, monitor.disk.fraction])
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        update([monitor.cpu, monitor.memory.fraction, monitor.disk.fraction])
    }

    private func update(_ values: [Double]) {
        let text = (values.first ?? 0).percent
        if text != cpuText { cpuText = text }
        guard shown.isEmpty || zip(values, shown).contains(where: { abs($0 - $1) >= 0.03 }) else { return }
        shown = values
        image = MenuBarIcon.make(values: values)
    }
}

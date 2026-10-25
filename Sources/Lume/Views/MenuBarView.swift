import SwiftUI
import AppKit

/// A compact glance from the menu bar: three small rings and a way back to the app.
struct MenuBarView: View {
    @EnvironmentObject private var monitor: SystemMonitor

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Lume").font(Theme.rounded(17, .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                Text(monitor.mood).font(Theme.label).foregroundStyle(Theme.secondary)
            }
            HStack(spacing: 8) {
                MiniRing(fraction: monitor.cpu, label: "Processor", hue: Theme.cpuHue)
                MiniRing(fraction: monitor.memory.fraction, label: "Memory", hue: Theme.memoryHue)
                MiniRing(fraction: monitor.disk.fraction, label: "Disk", hue: Theme.diskHue)
            }
            .padding(.vertical, 14)
            .glass(RoundedRectangle(cornerRadius: 20, style: .continuous))
            HStack {
                Button("Open Lume") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
                }
                .glassButton(prominent: true)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .glassButton()
            }
        }
        .padding(16)
        .frame(width: 300)
        .preferredColorScheme(.light)
    }
}

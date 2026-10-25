import SwiftUI
import AppKit

/// A compact glance from the menu bar: three numbers and a way back to the app.
struct MenuBarView: View {
    @EnvironmentObject private var monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            stat("Processor", monitor.cpu)
            stat("Memory", monitor.memory.fraction)
            stat("Disk", monitor.disk.fraction)
            Divider()
            HStack {
                Button("Open Lume") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 240)
    }

    private func stat(_ label: String, _ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(Theme.label)
                Spacer()
                Text("\(Int(fraction * 100))%").font(.system(size: 12, design: .rounded).monospacedDigit())
            }
            UsageBar(fraction: fraction, tint: Theme.tint(for: fraction))
        }
    }
}

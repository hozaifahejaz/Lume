import SwiftUI
import AppKit

/// A compact glance from the menu bar: a breathing orb, three numbers, a way back in.
struct MenuBarView: View {
    @EnvironmentObject private var monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 18) {
                Orb(load: monitor.load, size: 34)
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Lume").font(Theme.serif(22)).foregroundStyle(Theme.bone)
                    Text(monitor.mood).monoLabel(size: 8.5)
                }
                Spacer()
            }
            Hairline()
            stat("Processor", "\(Int((monitor.cpu * 100).rounded()))%", monitor.cpu)
            stat("Memory", monitor.memory.used.bytes, monitor.memory.fraction)
            stat("Disk free", monitor.disk.available.bytes, monitor.disk.fraction)
            Hairline()
            HStack {
                Button("Open Lume") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
                }
                .monoLabel(Theme.amber, size: 9.5)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .monoLabel(size: 9.5)
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .frame(width: 280)
        .background(Theme.ink)
        .preferredColorScheme(.dark)
    }

    private func stat(_ label: String, _ value: String, _ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).monoLabel(size: 9.5)
                Spacer()
                Text(value)
                    .font(Theme.serif(18).monospacedDigit())
                    .foregroundStyle(fraction > 0.85 ? Theme.coral : Theme.bone)
            }
            HairlineBar(fraction: fraction, tint: Theme.tint(for: fraction))
        }
    }
}

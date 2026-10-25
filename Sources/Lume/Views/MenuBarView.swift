import SwiftUI
import AppKit

/// A compact glance from the menu bar: the same three quiet stats as the Overview.
struct MenuBarView: View {
    @EnvironmentObject private var monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Lume").font(Theme.sectionTitle).foregroundStyle(Theme.ink)
                Spacer()
                Text(monitor.mood).font(Theme.caption).foregroundStyle(Theme.secondary)
            }
            HStack(spacing: 0) {
                stat("Processor", "\(Int((monitor.cpu * 100).rounded()))%", monitor.cpu)
                Hairline(vertical: true).padding(.horizontal, 12)
                stat("Memory", "\(Int((monitor.memory.fraction * 100).rounded()))%", monitor.memory.fraction)
                Hairline(vertical: true).padding(.horizontal, 12)
                stat("Disk", "\(Int((monitor.disk.fraction * 100).rounded()))%", monitor.disk.fraction)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .glass(RoundedRectangle(cornerRadius: 16, style: .continuous))
            HStack {
                Button("Quit Lume") { NSApp.terminate(nil) }
                    .glassButton()
                Spacer()
                Button("Open Lume") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
                }
                .glassButton(prominent: true)
            }
        }
        .padding(16)
        .frame(width: 320)
        .preferredColorScheme(.light)
    }

    private func stat(_ label: String, _ value: String, _ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.caption).foregroundStyle(Theme.secondary)
            Text(value)
                .font(.system(size: 24, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.isHigh(fraction) ? Theme.alert : Theme.ink)
            HairBar(fraction: fraction).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

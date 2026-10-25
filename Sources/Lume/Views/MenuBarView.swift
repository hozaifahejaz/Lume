import SwiftUI
import AppKit

/// A compact glance from the menu bar: the same three quiet stats as the Overview.
struct MenuBarView: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Lume").font(Theme.sectionTitle).foregroundStyle(Theme.ink)
                Spacer()
                Text(monitor.mood).font(Theme.caption).foregroundStyle(Theme.secondary)
            }
            HStack(spacing: 0) {
                stat("Processor", monitor.cpu.percent, monitor.cpu)
                Hairline(vertical: true).padding(.horizontal, 12)
                stat("Memory", monitor.memory.fraction.percent, monitor.memory.fraction,
                     alert: monitor.pressure == .critical)
                Hairline(vertical: true).padding(.horizontal, 12)
                stat("Disk", monitor.disk.fraction.percent, monitor.disk.fraction)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .glass(RoundedRectangle(cornerRadius: 16, style: .continuous))
            HStack {
                Button("Quit Lume") { NSApp.terminate(nil) }
                    .glassButton()
                Spacer()
                Button("Open Lume") {
                    MainWindow.openAction = openWindow
                    // Dismiss the panel first, so the main window comes forward instead of hiding behind it.
                    NSApp.keyWindow?.close()
                    MainWindow.open()
                }
                .glassButton(prominent: true)
            }
        }
        .padding(16)
        .frame(width: 320)
        .preferredColorScheme(.light)
    }

    private func stat(_ label: String, _ value: String, _ fraction: Double, alert: Bool? = nil) -> some View {
        let high = alert ?? Theme.isHigh(fraction)
        return VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.caption).foregroundStyle(Theme.secondary)
            Text(value)
                .font(.system(size: 24, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(high ? Theme.alert : Theme.ink)
            HairBar(fraction: fraction, alert: high).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

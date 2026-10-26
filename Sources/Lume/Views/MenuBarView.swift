import SwiftUI
import AppKit

/// A compact glance from the menu bar: the same three quiet stats as the Overview.
struct MenuBarView: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @EnvironmentObject private var diskSpace: DiskSpace
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var actions = QuickActions.shared

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
                stat("Disk", diskSpace.stats.fraction.percent, diskSpace.stats.fraction)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .glass(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button(actions.running == .cleaning ? "Cleaning…" : "Quick Clean") { actions.quickClean() }
                        .buttonStyle(PanelButtonStyle())
                        .help("Clears caches and logs, keeping those of open apps")
                    Button(actions.running == .freeingMemory ? "Freeing…" : "Free RAM…") { actions.freeRAM() }
                        .buttonStyle(PanelButtonStyle())
                        .help("Empties the file cache; asks for your password")
                }
                .disabled(actions.running != nil)
                let result = [actions.cleanResult, actions.memoryResult].compactMap { $0 }.joined(separator: " · ")
                if !result.isEmpty {
                    Text(result).font(Theme.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                }
            }
            Hairline()
            HStack {
                Button("Quit Lume") { NSApp.terminate(nil) }
                    .buttonStyle(PanelButtonStyle())
                Spacer()
                Button("Open Lume") {
                    MainWindow.openAction = openWindow
                    // Dismiss the panel first, so the main window comes forward instead of hiding behind it.
                    NSApp.keyWindow?.close()
                    MainWindow.open()
                }
                .buttonStyle(PanelButtonStyle(prominent: true))
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

/// The panel opens while Lume is usually in the background, where standard buttons draw in their
/// inactive state and look disabled. These capsules look the same whether or not Lume is frontmost.
private struct PanelButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, prominent: prominent)
    }

    /// A view of its own, so it can read whether the button is enabled.
    private struct Face: View {
        let configuration: Configuration
        let prominent: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            label.opacity(isEnabled ? 1 : 0.45)
        }

        private var label: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(prominent ? Color.white : Theme.ink)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(Capsule().fill(prominent ? Theme.accent : Color.black.opacity(0.06)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(prominent ? 0.25 : 0.6), lineWidth: 0.5))
                .opacity(configuration.isPressed ? 0.75 : 1)
                .contentShape(Capsule())
        }
    }
}

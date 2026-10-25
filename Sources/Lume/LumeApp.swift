import SwiftUI
import AppKit

@main
struct LumeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor: SystemMonitor
    @StateObject private var meter: MenuBarMeter
    @StateObject private var navigator = Navigator()

    init() {
        let monitor = SystemMonitor()
        _monitor = StateObject(wrappedValue: monitor)
        _meter = StateObject(wrappedValue: MenuBarMeter(monitor: monitor))
    }

    var body: some Scene {
        // A single window with an id, so the menu bar can reopen it after it is closed.
        Window("Lume", id: "main") {
            RootView()
                .environmentObject(monitor)
                .environmentObject(navigator)
                .frame(minWidth: 960, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1040, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(before: .toolbar) {
                ForEach(Array(Page.allCases.enumerated()), id: \.element) { index, page in
                    Button(page.rawValue) { navigator.show(page) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
                Divider()
                Button("Rescan") { navigator.rescan() }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
            }
        }

        Settings {
            SettingsView()
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(monitor)
        } label: {
            MenuBarLabel(meter: meter)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Launched via `swift run` there is no bundle, so promote to a regular app.
        NSApp.setActivationPolicy(.regular)
        // Set the icon explicitly so the Dock never shows a stale generic one; skipped under `swift run`.
        if let url = Bundle.main.url(forResource: "Lume", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the Dock icon with the window closed brings it back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainWindow.open() }
        return true
    }
}

/// Holds SwiftUI's openWindow action so AppKit code (the Dock) can reopen the main window.
@MainActor
enum MainWindow {
    static var openAction: OpenWindowAction?

    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        openAction?(id: "main")
    }
}

/// The menu bar icon, optionally followed by the processor percentage. It's always on screen,
/// so it also captures the openWindow action at launch.
private struct MenuBarLabel: View {
    @ObservedObject var meter: MenuBarMeter
    @Environment(\.openWindow) private var openWindow
    @AppStorage(MenuBarMeter.showsCPUKey) private var showsCPU = false

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: meter.image)
            if showsCPU {
                // A fixed two-digit width, so neighbouring menu bar items don't shift as the value changes.
                ZStack(alignment: .trailing) {
                    Text("88%").hidden()
                    Text(meter.cpuText)
                }
                .monospacedDigit()
            }
        }
        .onAppear { MainWindow.openAction = openWindow }
    }
}

import SwiftUI
import AppKit

@main
struct LumeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor: SystemMonitor
    @StateObject private var meter: MenuBarMeter

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
                .frame(minWidth: 960, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1040, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

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

/// The menu bar icon; it's always on screen, so it also captures the openWindow action at launch.
private struct MenuBarLabel: View {
    @ObservedObject var meter: MenuBarMeter
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: meter.image)
            .onAppear { MainWindow.openAction = openWindow }
    }
}

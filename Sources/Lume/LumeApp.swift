import SwiftUI
import AppKit

@main
struct LumeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Plain constants, not @StateObject: the App would otherwise observe them, and every sample
    // (or tab change) would re-evaluate the whole scene, rebuilding the main menu and the menu bar item.
    // The views that show their values observe them instead.
    private let monitor: SystemMonitor
    private let meter: MenuBarMeter
    private let navigator = Navigator()

    init() {
        let monitor = SystemMonitor()
        self.monitor = monitor
        meter = MenuBarMeter(monitor: monitor)
        let diskSpace = monitor.diskSpace
        QuickActions.shared.onCleaned = { diskSpace.refresh() }
    }

    var body: some Scene {
        // A single window with an id, so the menu bar can reopen it after it is closed.
        Window("Lume", id: "main") {
            RootView()
                .environmentObject(monitor)
                .environmentObject(monitor.diskSpace)
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
                Button("Command Bar…") { navigator.toggleCommandBar() }
                    .keyboardShortcut("k", modifiers: .command)
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
                .environmentObject(monitor.diskSpace)
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

        // Closing the last window leaves Lume running in the menu bar alone, without a Dock icon;
        // a window appearing again (the main one or Settings) brings the Dock icon back.
        let center = NotificationCenter.default
        for name in [NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                // Let the closing window finish leaving before looking.
                DispatchQueue.main.async { MainActor.assumeIsolated { Dock.update() } }
            }
        }
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Dock.update() }
        }

        MainActor.assumeIsolated { QuickActions.shared.startSchedule() }
    }

    /// Lume keeps running in the menu bar after its window closes; Quit (⌘Q, the Dock or the panel) ends it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Right-clicking the Dock icon offers the two quick actions.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let busy = MainActor.assumeIsolated { QuickActions.shared.running != nil }
        for (title, action) in [("Quick Clean", #selector(quickClean)), ("Free RAM…", #selector(freeRAM))] {
            let item = NSMenuItem(title: title, action: busy ? nil : action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    @objc private func quickClean() { MainActor.assumeIsolated { QuickActions.shared.quickClean() } }
    @objc private func freeRAM() { MainActor.assumeIsolated { QuickActions.shared.freeRAM() } }

    /// Opening Lume again from Finder or the Dock with the window closed brings it back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainWindow.open() }
        return true
    }
}

/// Shows the Dock icon only while Lume has a window of its own open (or in the Dock, minimised).
@MainActor
enum Dock {
    /// The main window and Settings; the menu bar panel and the status item are panels and don't count.
    private static var hasAppWindow: Bool {
        NSApp.windows.contains { window in
            window.styleMask.contains(.titled) && !(window is NSPanel)
                && (window.isVisible || window.isMiniaturized)
        }
    }

    static func update() {
        let policy: NSApplication.ActivationPolicy = hasAppWindow ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }

    /// Before a window opens, so it arrives with the Dock icon and the menus already in place.
    static func show() {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
    }
}

/// Holds SwiftUI's openWindow action so AppKit code (the Dock) can reopen the main window.
@MainActor
enum MainWindow {
    static var openAction: OpenWindowAction?

    private static var window: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }
    }

    /// True while some part of the main window can be seen.
    static var isOnScreen: Bool {
        guard let window else { return false }
        return window.isVisible && window.occlusionState.contains(.visible)
    }

    static func open() {
        Dock.show()
        if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
        // Already there: just bring it forward. openWindow rebuilds the scene list and menus each call,
        // which made every ⌘1–4 press do a few milliseconds of needless work.
        // A closed window is kept alive, so it can come straight back too. Ordering it in right away
        // also means the Dock icon stays when the menu bar panel's own closing is noticed a moment later.
        if let window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            if !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
            return
        }
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

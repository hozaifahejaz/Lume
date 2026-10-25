import Foundation
import AppKit

struct StartupItem: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let label: String
    let program: String
    let isUserScope: Bool
    var isEnabled: Bool

    var displayName: String {
        // "com.vendor.product.agent" reads better as "product agent".
        let parts = label.split(separator: ".")
        let meaningful = parts.count > 2 ? parts.dropFirst(2) : parts[...]
        return meaningful.joined(separator: " ")
    }
}

/// Reads launch agents, the background helpers apps install to run at login.
/// User agents can be paused by moving the plist into a sibling "Disabled" folder,
/// which is fully reversible. System-wide agents are shown read-only.
@MainActor
final class StartupItems: ObservableObject {
    @Published private(set) var items: [StartupItem] = []

    private let fm = FileManager.default
    private var userAgents: URL { fm.homeDirectoryForCurrentUser.appending(path: "Library/LaunchAgents") }
    private var userDisabled: URL { fm.homeDirectoryForCurrentUser.appending(path: "Library/LaunchAgents (Disabled by Lume)") }
    private let systemAgents = URL(fileURLWithPath: "/Library/LaunchAgents")

    func reload() {
        var result: [StartupItem] = []
        result += read(userAgents, user: true, enabled: true)
        result += read(userDisabled, user: true, enabled: false)
        result += read(systemAgents, user: false, enabled: true)
        items = result.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func setEnabled(_ item: StartupItem, _ enabled: Bool) {
        guard item.isUserScope, item.isEnabled != enabled else { return }
        let destinationFolder = enabled ? userAgents : userDisabled
        try? fm.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let destination = destinationFolder.appending(path: item.url.lastPathComponent)
        if !enabled { launchctl(["bootout", "gui/\(getuid())", item.url.path]) }
        do {
            try fm.moveItem(at: item.url, to: destination)
            if enabled { launchctl(["bootstrap", "gui/\(getuid())", destination.path]) }
        } catch {
            NSSound.beep()
        }
        reload()
    }

    func reveal(_ item: StartupItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func read(_ folder: URL, user: Bool, enabled: Bool) -> [StartupItem] {
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "plist" }.compactMap { url in
            guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else { return nil }
            let label = dict["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
            let program = (dict["Program"] as? String)
                ?? (dict["ProgramArguments"] as? [String])?.first
                ?? ""
            return StartupItem(url: url, label: label, program: program, isUserScope: user, isEnabled: enabled)
        }
    }

    private func launchctl(_ args: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = args
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {}
    }
}

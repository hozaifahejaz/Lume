import Foundation
import AppKit
import UserNotifications

/// Quick Clean and Free RAM, shared by the Memory page, the menu bar panel and the Dock menu,
/// so they work with the window closed and never run twice at once.
@MainActor
final class QuickActions: ObservableObject {
    static let shared = QuickActions()

    /// The same Cleaner the Clean page shows, so a Quick Clean appears there too.
    let cleaner = Cleaner()
    /// Called after a Quick Clean, to re-read free disk space.
    var onCleaned: (() -> Void)?

    enum Job { case cleaning, freeingMemory }
    @Published private(set) var running: Job?
    /// The last outcome in a few words, such as "Freed 1.2 GB".
    @Published private(set) var cleanResult: String?
    @Published private(set) var memoryResult: String?

    func quickClean() {
        guard running == nil else { return }
        running = .cleaning
        Task {
            let freed = await cleaner.quickClean()
            running = nil
            guard let freed else { return }
            let text = freed > 0 ? "Freed \(freed.bytes)" : "Nothing to clear right now"
            cleanResult = text
            onCleaned?()
            Self.notify(title: "Quick Clean", body: text)
        }
    }

    /// Runs macOS's own `purge`, which empties the file cache. It needs an administrator password,
    /// so macOS asks for it each time.
    func freeRAM() {
        guard running == nil else { return }
        running = .freeingMemory
        Task {
            let before = SystemMonitor.readMemory().free
            let outcome = await Task.detached(priority: .userInitiated) { Self.purge() }.value
            running = nil
            switch outcome {
            case .done:
                let after = SystemMonitor.readMemory().free
                let text = "Free memory \(before.bytes) → \(after.bytes)"
                memoryResult = text
                Self.notify(title: "Free RAM", body: text)
            case .cancelled:
                break
            case .failed:
                memoryResult = "Couldn’t free memory"
            }
        }
    }

    enum Outcome: Sendable { case done, cancelled, failed }

    nonisolated private static func purge() -> Outcome {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "do shell script \"/usr/sbin/purge\" with administrator privileges"]
        let errors = Pipe()
        task.standardOutput = FileHandle.nullDevice
        task.standardError = errors
        do { try task.run() } catch { return .failed }
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        task.waitUntilExit()
        if task.terminationStatus == 0 { return .done }
        // -128 is "User canceled" from the password prompt.
        return message.contains("-128") ? .cancelled : .failed
    }

    /// A banner with the result, for actions started from the Dock or the menu bar with no window open.
    private static func notify(title: String, body: String) {
        // Only a real app bundle can post notifications; `swift run` can't.
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundlePath.hasSuffix(".app") else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}

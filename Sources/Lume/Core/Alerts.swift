import Foundation
import UserNotifications

/// Posts a banner. Only a real app bundle can post notifications; `swift run` can't.
enum Notifier {
    static func post(title: String, body: String) {
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

/// Two gentle warnings, each at most once a day: the disk under 10% free, and memory pressure
/// that stays elevated for five minutes. Both ride on readings Lume already takes, so they add no polling.
@MainActor
enum Alerts {
    static let enabledKey = "alertsEnabled"
    private static let pressureLimit: TimeInterval = 5 * 60
    private static var pressureSince: Date?

    private static var enabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// From DiskSpace, every 30 seconds.
    static func check(disk: DiskStats) {
        guard enabled, disk.nearlyFull else { return }
        post("Your disk is nearly full", "\(disk.available.bytes) left. Clean in Lume can clear caches and old files.",
             key: "alertedDisk")
    }

    /// From SystemMonitor, on every sample.
    static func check(pressure: SystemMonitor.Pressure) {
        guard pressure != .normal else { pressureSince = nil; return }
        let since = pressureSince ?? Date()
        pressureSince = since
        guard enabled, Date().timeIntervalSince(since) >= pressureLimit else { return }
        post("Memory pressure is \(pressure.word)", "Quitting apps you aren’t using frees the most memory.",
             key: "alertedPressure")
    }

    /// Once per day per alert.
    private static func post(_ title: String, _ body: String, key: String) {
        let defaults = UserDefaults.standard
        if let last = defaults.object(forKey: key) as? Date, Date().timeIntervalSince(last) < 24 * 60 * 60 { return }
        defaults.set(Date(), forKey: key)
        Notifier.post(title: title, body: body)
    }
}

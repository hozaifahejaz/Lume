import Foundation
import IOKit

/// The built-in battery's health, read from IOKit's AppleSmartBattery. Desktops have none.
struct BatteryHealth: Equatable {
    /// Maximum capacity as a fraction of what the battery held when new.
    let capacity: Double
    let cycles: Int

    /// Apple recommends service once a battery holds less than 80% of its original charge.
    var needsService: Bool { capacity < 0.8 }
    var condition: String { needsService ? "Service recommended" : "Normal" }

    /// Nil on Macs without a battery. Cheap, but it touches IOKit, so call it off the main actor.
    static func read() -> BatteryHealth? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as NSDictionary? as? [String: Any],
              properties["BatteryInstalled"] as? Bool ?? true else { return nil }

        let cycles = properties["CycleCount"] as? Int ?? 0
        let max = properties["MaxCapacity"] as? Int ?? 0
        // Apple silicon keeps the design figure inside BatteryData.
        let data = properties["BatteryData"] as? [String: Any]
        let design = properties["DesignCapacity"] as? Int ?? data?["DesignCapacity"] as? Int ?? 0
        // Apple silicon reports MaxCapacity as a percentage already; Intel Macs report it in mAh.
        let capacity: Double
        if max > 0 && max <= 100 && (design == 0 || design > 100) {
            capacity = Double(max) / 100
        } else if let raw = properties["AppleRawMaxCapacity"] as? Int, design > 0 {
            capacity = Double(raw) / Double(design)
        } else if max > 0 && design > 0 {
            capacity = Double(max) / Double(design)
        } else {
            return nil
        }
        return BatteryHealth(capacity: min(capacity, 1), cycles: cycles)
    }
}

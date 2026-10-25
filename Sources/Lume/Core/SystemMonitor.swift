import Foundation
import Darwin

/// Samples CPU, memory and disk once a second using Mach and Foundation APIs.
@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var cpu: Double = 0
    @Published private(set) var cpuHistory: [Double] = Array(repeating: 0, count: 60)
    @Published private(set) var memory = MemoryStats()
    @Published private(set) var disk = DiskStats()

    private var timer: Timer?
    private var previousTicks: [CPUTicks] = []

    init() {
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    func sample() {
        let ticks = Self.readCPUTicks()
        if !previousTicks.isEmpty, previousTicks.count == ticks.count {
            var busy: Double = 0
            var total: Double = 0
            for (now, before) in zip(ticks, previousTicks) {
                let b = Double(now.busy &- before.busy)
                busy += b
                total += b + Double(now.idle &- before.idle)
            }
            cpu = total > 0 ? busy / total : 0
            cpuHistory.removeFirst()
            cpuHistory.append(cpu)
        }
        previousTicks = ticks
        memory = Self.readMemory()
        disk = Self.readDisk()
    }

    // MARK: CPU

    struct CPUTicks {
        var busy: UInt32
        var idle: UInt32
    }

    private static func readCPUTicks() -> [CPUTicks] {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        var ticks: [CPUTicks] = []
        for i in 0..<Int(cpuCount) {
            let base = Int(CPU_STATE_MAX) * i
            let user = UInt32(bitPattern: info[base + Int(CPU_STATE_USER)])
            let system = UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)])
            let nice = UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            let idle = UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])
            ticks.append(CPUTicks(busy: user &+ system &+ nice, idle: idle))
        }
        return ticks
    }

    // MARK: Memory

    struct MemoryStats {
        var total: UInt64 = ProcessInfo.processInfo.physicalMemory
        var used: UInt64 = 0
        var wired: UInt64 = 0
        var compressed: UInt64 = 0
        var app: UInt64 = 0
        var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    }

    private static func readMemory() -> MemoryStats {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var out = MemoryStats()
        guard result == KERN_SUCCESS else { return out }
        let page = UInt64(vm_kernel_page_size)
        // Matches Activity Monitor's "Memory Used" = app + wired + compressed.
        let internalPages = UInt64(stats.internal_page_count)
        let purgeablePages = UInt64(stats.purgeable_count)
        out.app = (internalPages > purgeablePages ? internalPages - purgeablePages : 0) * page
        out.wired = UInt64(stats.wire_count) * page
        out.compressed = UInt64(stats.compressor_page_count) * page
        out.used = out.app + out.wired + out.compressed
        return out
    }

    // MARK: Disk

    struct DiskStats {
        var total: Int64 = 0
        var available: Int64 = 0
        var used: Int64 { total - available }
        var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    }

    private static func readDisk() -> DiskStats {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return DiskStats() }
        return DiskStats(
            total: Int64(values.volumeTotalCapacity ?? 0),
            available: values.volumeAvailableCapacityForImportantUsage ?? 0
        )
    }
}

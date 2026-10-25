import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @ObservedObject var processes: ProcessList
    let goTo: (Page) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            PageHeader(title: headline, subtitle: detail) {
                if monitor.diskNearlyFull {
                    Button("Free Up Space…") { goTo(.clean) }
                        .glassButton()
                }
            }

            GlassPanel(fill: false) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 0) {
                        stat("Processor", monitor.cpu.percent,
                             ["\(ProcessInfo.processInfo.activeProcessorCount) cores", Self.coreKinds], monitor.cpu)
                        Hairline(vertical: true).padding(.horizontal, 20)
                        stat("Memory", monitor.memory.used.bytes,
                             ["of \(monitor.memory.total.bytes)", "Pressure \(monitor.pressure.word)"],
                             monitor.memory.fraction, alert: monitor.pressure == .critical)
                        Hairline(vertical: true).padding(.horizontal, 20)
                        stat("Disk", monitor.disk.used.bytes,
                             ["of \(monitor.disk.total.bytes)", "\(monitor.disk.available.bytes) available"],
                             monitor.disk.fraction)
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    Hairline()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Processor, last minute").font(Theme.caption).foregroundStyle(Theme.secondary)
                            Spacer()
                            Text(monitor.cpu.percent).font(Theme.digits).foregroundStyle(Theme.secondary)
                        }
                        Sparkline(values: monitor.cpuHistory)
                            .frame(height: 32)
                    }
                }
            }

            GlassPanel {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Activity").font(Theme.sectionTitle).foregroundStyle(Theme.ink)
                        Spacer()
                        Picker("", selection: $processes.sort) {
                            ForEach(ProcessList.Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    .padding(.leading, 8)

                    FittingRows(items: processes.processes, rowHeight: 34) { process in
                        ProcessRow(process: process, sort: processes.sort) {
                            processes.quit(process)
                        }
                    }
                }
            }
        }
        .onAppear { processes.start() }
        .onDisappear { processes.stop() }
    }

    /// `alert` turns the number red; by default that happens past 85%. Memory passes it in,
    /// because a nearly full memory figure is normal on macOS and only high pressure is a problem.
    private func stat(_ label: String, _ value: String, _ captions: [String], _ fraction: Double,
                      alert: Bool? = nil) -> some View {
        let high = alert ?? Theme.isHigh(fraction)
        return VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.caption).foregroundStyle(Theme.secondary)
            Text(value)
                .font(Theme.number)
                .foregroundStyle(high ? Theme.alert : Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            VStack(alignment: .leading, spacing: 2) {
                ForEach(captions.filter { !$0.isEmpty }, id: \.self) { caption in
                    Text(caption).font(Theme.caption).foregroundStyle(Theme.tertiary).lineLimit(1)
                }
            }
            HairBar(fraction: fraction, alert: high).padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "4 performance · 6 efficiency" on Apple silicon; empty where the split isn't reported.
    private static let coreKinds: String = {
        func int(_ name: String) -> Int {
            var value: Int32 = 0
            var size = MemoryLayout<Int32>.size
            return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : 0
        }
        func string(_ name: String) -> String {
            var size = 0
            guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
            var buffer = [CChar](repeating: 0, count: size)
            guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "" }
            return String(cString: buffer)
        }
        let levels = int("hw.nperflevels")
        guard levels > 1 else { return "" }
        return (0..<levels).compactMap { level -> String? in
            let count = int("hw.perflevel\(level).physicalcpu")
            let name = string("hw.perflevel\(level).name").lowercased()
            return count > 0 && !name.isEmpty ? "\(count) \(name)" : nil
        }.joined(separator: " · ")
    }()

    private var headline: String {
        switch monitor.load {
        case .smooth: return "Your Mac is running smoothly."
        case .busy: return "Your Mac is busy."
        case .heavy: return "Your Mac is under heavy load."
        }
    }

    private var detail: String {
        var parts: [String] = []
        if monitor.cpu >= 0.7 { parts.append("The processor is busy at \(monitor.cpu.percent).") }
        switch monitor.pressure {
        case .normal: break
        case .warning: parts.append("Memory pressure is elevated.")
        case .critical: parts.append("Memory pressure is high.")
        }
        if parts.isEmpty { parts.append("Processor and memory have plenty of headroom.") }
        if monitor.diskNearlyFull { parts.append("Disk is nearly full.") }
        return parts.joined(separator: " ")
    }
}

private struct ProcessRow: View {
    let process: ProcessUsage
    let sort: ProcessList.Sort
    let onQuit: () -> Void
    @StateObject private var hovering = ViewState(false)

    var body: some View {
        HStack(spacing: 12) {
            if let image = AppIcons.forProcess(process.id, appPath: process.appPath) {
                AppIconView(image: image)
            } else {
                IconTile(symbol: ProcessSymbol.forPath(process.path), size: Theme.rowIcon)
            }
            Text(process.name)
                .font(Theme.body)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 16)
            Text(value)
                .font(Theme.digits)
                .foregroundStyle(Theme.secondary)
            // Only regular apps can be quit; system and background processes never show the button.
            Button(action: onQuit) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.tertiary)
            }
            .buttonStyle(.plain)
            .help("Quit \(process.name)")
            .accessibilityLabel("Quit \(process.name)")
            .opacity(process.canQuit && hovering.value ? 1 : 0)
            .disabled(!process.canQuit)
        }
        .frame(maxHeight: .infinity)
        .onHover { hovering.value = $0 }
        .hoverWash()
    }

    private var value: String {
        switch sort {
        case .memory: return process.memory.bytes
        case .cpu: return String(format: "%.1f%%", process.cpu)
        }
    }
}

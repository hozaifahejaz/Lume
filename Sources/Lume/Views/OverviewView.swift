import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @ObservedObject var processes: ProcessList
    let goTo: (Page) -> Void

    var body: some View {
        VStack(spacing: 26) {
            ZStack {
                Color.clear
                    .frame(width: 330, height: 330)
                    .glass(Circle())
                RingGauge(
                    values: [monitor.cpu, monitor.memory.fraction, monitor.disk.fraction],
                    hues: [Theme.cpuHue, Theme.memoryHue, Theme.diskHue]
                )
                .frame(width: 286, height: 286)
                VStack(spacing: 4) {
                    Text(monitor.mood)
                        .font(Theme.rounded(28, .semibold))
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.opacity)
                    Text(greeting).font(Theme.label).foregroundStyle(Theme.secondary)
                }
                .animation(.smooth, value: monitor.mood)
            }
            .padding(.top, 4)

            HStack(spacing: 14) {
                chip("Processor", "\(Int((monitor.cpu * 100).rounded()))%",
                     "\(ProcessInfo.processInfo.activeProcessorCount) cores", monitor.cpu, Theme.cpuHue)
                chip("Memory", monitor.memory.used.bytes, "of \(monitor.memory.total.bytes)",
                     monitor.memory.fraction, Theme.memoryHue)
                chip("Disk", monitor.disk.available.bytes, "free", monitor.disk.fraction, Theme.diskHue)
            }

            if monitor.disk.fraction > 0.8 {
                Button { goTo(.clean) } label: {
                    Label("Your disk is getting full. Free up space", systemImage: "sparkles")
                }
                .glassButton(prominent: true)
            }

            activity
        }
        .onAppear { processes.start() }
        .onDisappear { processes.stop() }
    }

    private func chip(_ label: String, _ value: String, _ caption: String, _ fraction: Double, _ hue: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(Theme.tint(for: fraction, base: hue)).frame(width: 8, height: 8)
                Text(label).font(Theme.label).foregroundStyle(Theme.secondary)
            }
            Text(value)
                .font(Theme.number(30))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
                .animation(.smooth, value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption).font(Theme.label).foregroundStyle(Theme.tertiary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
    }

    private var activity: some View {
        GlassSlab(padding: 18) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Activity").font(Theme.rounded(17, .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Picker("", selection: $processes.sort) {
                        ForEach(ProcessList.Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 150)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)

                ForEach(processes.processes) { process in
                    ProcessRow(process: process, sort: processes.sort, total: monitor.memory.total) {
                        processes.quit(process)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Processor, last minute").font(Theme.label).foregroundStyle(Theme.secondary)
                        Spacer()
                        Text("\(Int((monitor.cpu * 100).rounded()))%")
                            .font(Theme.number(13, .medium))
                            .foregroundStyle(Theme.ink)
                    }
                    Sparkline(values: monitor.cpuHistory, tint: Theme.tint(for: monitor.cpu))
                        .frame(height: 44)
                }
                .padding(.horizontal, 8)
                .padding(.top, 18)
            }
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }
}

private struct ProcessRow: View {
    let process: ProcessUsage
    let sort: ProcessList.Sort
    let total: UInt64
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text(process.name)
                .font(Theme.body)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .frame(width: 210, alignment: .leading)
            SlimBar(fraction: fraction, tint: sort == .memory ? Theme.memoryHue : Theme.cpuHue)
            Text(value)
                .font(Theme.number(12, .medium))
                .foregroundStyle(Theme.secondary)
                .frame(width: 76, alignment: .trailing)
            Button(action: onQuit) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.tertiary)
            }
            .buttonStyle(.plain)
            .help("Quit \(process.name)")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .hoverLift()
    }

    private var fraction: Double {
        switch sort {
        case .memory: return total > 0 ? Double(process.memory) / Double(total) * 4 : 0
        case .cpu: return process.cpu / 100
        }
    }

    private var value: String {
        switch sort {
        case .memory: return process.memory.bytes
        case .cpu: return String(format: "%.1f%%", process.cpu)
        }
    }
}

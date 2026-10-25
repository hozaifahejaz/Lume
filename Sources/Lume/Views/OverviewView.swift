import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @ObservedObject var processes: ProcessList
    let goTo: (Page) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LoadArcs(values: [monitor.cpu, monitor.memory.fraction, monitor.disk.fraction], diameter: 272)
                Orb(load: monitor.load, size: 200)
            }
            .frame(height: 400)

            Text(monitor.mood)
                .font(Theme.serif(32))
                .foregroundStyle(Theme.bone)
                .contentTransition(.opacity)
                .animation(.smooth, value: monitor.mood)
                .padding(.top, 4)
            Text("\(greeting) · arcs show processor, memory, disk")
                .monoLabel(size: 9.5)
                .padding(.top, 12)

            HStack(spacing: 0) {
                stat("Processor", "\(Int((monitor.cpu * 100).rounded()))%",
                     "\(ProcessInfo.processInfo.activeProcessorCount) cores", monitor.cpu)
                Rectangle().fill(Theme.hairline).frame(width: 0.5, height: 56)
                stat("Memory", monitor.memory.used.bytes, "of \(monitor.memory.total.bytes)", monitor.memory.fraction)
                Rectangle().fill(Theme.hairline).frame(width: 0.5, height: 56)
                stat("Disk", monitor.disk.available.bytes, "free", monitor.disk.fraction)
            }
            .padding(.top, 52)

            if monitor.disk.fraction > 0.8 {
                Button("Disk is nearly full · Clean →") { goTo(.clean) }
                    .buttonStyle(MonoButtonStyle())
                    .padding(.top, 32)
            }

            activity.padding(.top, 72)
        }
        .onAppear { processes.start() }
        .onDisappear { processes.stop() }
    }

    private func stat(_ label: String, _ value: String, _ caption: String, _ fraction: Double) -> some View {
        VStack(spacing: 8) {
            Text(label).monoLabel()
            Text(value)
                .font(Theme.serif(30).monospacedDigit())
                .foregroundStyle(fraction > 0.85 ? Theme.coral : Theme.bone)
                .contentTransition(.numericText())
                .animation(.smooth, value: value)
            Text(caption).monoLabel(Theme.bone.opacity(0.3), size: 9)
        }
        .frame(maxWidth: .infinity)
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Activity").monoLabel()
                Spacer()
                HStack(spacing: 18) {
                    ForEach(ProcessList.Sort.allCases, id: \.self) { sort in
                        Button(sort.rawValue) { processes.sort = sort }
                            .buttonStyle(.plain)
                            .monoLabel(processes.sort == sort ? Theme.amber : Theme.boneDim)
                    }
                }
            }
            .padding(.bottom, 14)
            Hairline()

            ForEach(processes.processes) { process in
                ProcessRow(process: process, sort: processes.sort, total: monitor.memory.total) {
                    processes.quit(process)
                }
                Hairline()
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Processor · last minute").monoLabel()
                    Spacer()
                    Text("\(Int((monitor.cpu * 100).rounded()))%")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.bone)
                }
                GlowLine(values: monitor.cpuHistory, tint: Theme.tint(for: monitor.cpu))
                    .frame(height: 56)
            }
            .padding(.top, 40)
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
    @StateObject private var hoverState = ViewState(false)

    var body: some View {
        HStack(spacing: 20) {
            Text(process.name)
                .font(Theme.body)
                .foregroundStyle(Theme.bone.opacity(hoverState.value ? 1 : 0.85))
                .lineLimit(1)
                .frame(width: 220, alignment: .leading)
            HairlineBar(fraction: fraction, tint: Theme.amber.opacity(0.85))
            Text(value)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.boneDim)
                .frame(width: 76, alignment: .trailing)
            Button(action: onQuit) {
                Text("Quit").monoLabel(Theme.coral, size: 9.5)
            }
            .buttonStyle(.plain)
            .help("Quit \(process.name)")
            .frame(width: 44)
            .opacity(hoverState.value ? 1 : 0)
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onHover { hoverState.value = $0 }
        .animation(.smooth(duration: 0.2), value: hoverState.value)
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

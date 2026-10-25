import SwiftUI

struct CleanView: View {
    @ObservedObject var cleaner: Cleaner
    @EnvironmentObject private var monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            PageHeader(title: headline,
                       subtitle: "Caches and logs your Mac and apps recreate on their own when they need them.")

            HStack(alignment: .top, spacing: Theme.gap) {
                GlassPanel {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("What to clean")
                            .font(Theme.sectionTitle)
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                        ForEach(Array(cleaner.categories.enumerated()), id: \.element.id) { index, category in
                            if index > 0 { Hairline().padding(.leading, 48) }
                            row(category)
                        }
                        if !cleaner.unreadable.isEmpty {
                            Label("Locked folders need Full Disk Access in System Settings › Privacy & Security.",
                                  systemImage: "lock")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.tertiary)
                                .padding(.horizontal, 8)
                                .padding(.top, 12)
                        }
                    }
                }

                GlassPanel {
                    VStack(spacing: 4) {
                        Spacer(minLength: 0)
                        Text(eyebrow).font(Theme.caption).foregroundStyle(Theme.secondary)
                        Text(bigNumber)
                            .font(Theme.number)
                            .foregroundStyle(Theme.ink)
                            .contentTransition(.numericText(countsDown: true))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        action.padding(.top, 20)
                        Text(footnote)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(width: 280)
            }
            // Both panels take the height of the taller one's content, not the whole window.
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .animation(.smooth(duration: 0.6), value: cleaner.phase)
        .animation(.smooth(duration: 0.6), value: cleaner.selectedTotal)
        .task { if cleaner.phase == .idle { await cleaner.scan() } }
        .onChange(of: cleaner.phase) { _, phase in
            if case .done = phase { monitor.refreshDisk() }
        }
    }

    private var headline: String {
        switch cleaner.phase {
        case .idle, .scanning: return "Looking for files to clear…"
        case .cleaning: return "Cleaning…"
        case .done(let freed): return "Freed \(freed.bytes)."
        case .ready:
            let total = cleaner.categories.compactMap { cleaner.sizes[$0.id] }.reduce(0, +)
            // In-use and protected files are skipped, so this is an upper bound.
            return total > 0 ? "Up to \(total.bytes) can be cleared." : "Nothing to clear right now."
        }
    }

    private var eyebrow: String {
        if case .done = cleaner.phase { return "Freed" }
        return "Selected"
    }

    private var footnote: String {
        if case .done = cleaner.phase { return "Your Mac rebuilds what it needs, when it needs it." }
        return "Press and hold to confirm."
    }

    private var bigNumber: String {
        if case .done(let freed) = cleaner.phase { return freed.bytes }
        return cleaner.selectedTotal.bytes
    }

    @ViewBuilder private var action: some View {
        switch cleaner.phase {
        case .done:
            Button("Scan Again") { Task { await cleaner.scan() } }
                .glassButton()
                .controlSize(.large)
                .frame(height: 148)
        default:
            HoldButton(
                enabled: cleaner.phase == .ready && cleaner.selectedTotal > 0,
                busy: cleaner.phase != .ready
            ) {
                Task { await cleaner.clean() }
            }
        }
    }

    private func row(_ category: JunkCategory) -> some View {
        let missing = cleaner.missing.contains(category.id)
        let locked = cleaner.unreadable.contains(category.id)
        let isOn = Binding(
            get: { cleaner.selected.contains(category.id) && !locked && !missing },
            set: { on in
                if on { cleaner.selected.insert(category.id) } else { cleaner.selected.remove(category.id) }
            }
        )
        return HStack(spacing: 12) {
            IconTile(symbol: category.symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name).font(Theme.body.weight(.medium)).foregroundStyle(Theme.ink)
                Text(category.detail).font(Theme.caption).foregroundStyle(Theme.secondary)
            }
            Spacer()
            if missing {
                Text("Not found")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.tertiary)
            } else if locked {
                Label("Needs access", systemImage: "lock")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.tertiary)
            } else if let size = cleaner.sizes[category.id] {
                Text(size.bytes)
                    .font(Theme.digits)
                    .foregroundStyle(Theme.secondary)
            } else {
                ProgressView().controlSize(.mini)
            }
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(Theme.graphite)
                .disabled(locked || missing)
        }
        .frame(height: 52)
        .opacity(locked || missing ? 0.6 : 1)
        .hoverWash()
    }
}

/// Press and hold for 1.2s while the ring fills; releasing early cancels.
private struct HoldButton: View {
    let enabled: Bool
    let busy: Bool
    let onComplete: () -> Void
    @StateObject private var progress = ViewState<Double>(0)
    private let duration = 1.2

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().stroke(Theme.track, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress.value)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .opacity(progress.value > 0 ? 1 : 0)
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 84, height: 84)
                    .overlay {
                        if busy {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 26, weight: .medium))
                                .foregroundStyle(.white)
                        }
                    }
                    .scaleEffect(progress.value > 0 ? 0.94 : 1)
            }
            .frame(width: 108, height: 108)
            .contentShape(Circle())
            .onLongPressGesture(minimumDuration: duration, maximumDistance: 40) {
                guard enabled else { return }
                onComplete()
                withAnimation(.smooth(duration: 0.5)) { progress.value = 0 }
            } onPressingChanged: { pressing in
                guard enabled else { return }
                if pressing {
                    withAnimation(.linear(duration: duration)) { progress.value = 1 }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { progress.value = 0 }
                }
            }
            .allowsHitTesting(enabled)

            Text("Hold to Clean").font(Theme.sectionTitle).foregroundStyle(enabled ? Theme.ink : Theme.tertiary)
        }
        .opacity(enabled || busy ? 1 : 0.45)
    }
}

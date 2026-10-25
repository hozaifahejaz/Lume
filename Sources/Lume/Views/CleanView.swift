import SwiftUI

struct CleanView: View {
    @ObservedObject var cleaner: Cleaner

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Clean", subtitle: "Clear out files your Mac and apps can safely rebuild.")

            GlassSlab(padding: 32) {
                HStack(alignment: .center, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(eyebrow).font(Theme.label).foregroundStyle(Theme.secondary)
                        Text(bigNumber)
                            .font(Theme.number(76))
                            .foregroundStyle(Theme.ink)
                            .contentTransition(.numericText(countsDown: true))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(caption).font(Theme.body).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    action
                }
            }

            GlassSlab(padding: 10) {
                VStack(spacing: 2) {
                    ForEach(cleaner.categories) { category in
                        row(category)
                    }
                }
            }

            if !cleaner.unreadable.isEmpty {
                Label("Some folders need Full Disk Access. Grant it in System Settings › Privacy & Security.",
                      systemImage: "lock")
                    .font(Theme.label)
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 8)
            }
        }
        .animation(.smooth(duration: 0.6), value: cleaner.phase)
        .animation(.smooth(duration: 0.6), value: cleaner.selectedTotal)
        .task { if cleaner.phase == .idle { await cleaner.scan() } }
    }

    private var eyebrow: String {
        switch cleaner.phase {
        case .idle, .scanning: return "Scanning…"
        case .cleaning: return "Cleaning…"
        case .done: return "Freed"
        case .ready: return "Ready to clean"
        }
    }

    private var caption: String {
        switch cleaner.phase {
        case .done: return "Your Mac rebuilds what it needs, when it needs it."
        default: return "Caches and logs are recreated automatically."
        }
    }

    private var bigNumber: String {
        if case .done(let freed) = cleaner.phase { return freed.bytes }
        return cleaner.selectedTotal.bytes
    }

    @ViewBuilder private var action: some View {
        switch cleaner.phase {
        case .done:
            Button("Scan again") { Task { await cleaner.scan() } }
                .glassButton()
                .controlSize(.large)
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
        let locked = cleaner.unreadable.contains(category.id)
        let isOn = Binding(
            get: { cleaner.selected.contains(category.id) && !locked },
            set: { on in
                if on { cleaner.selected.insert(category.id) } else { cleaner.selected.remove(category.id) }
            }
        )
        return HStack(spacing: 14) {
            IconBadge(symbol: category.symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name).font(Theme.rounded(15, .medium)).foregroundStyle(Theme.ink)
                Text(category.detail).font(Theme.label).foregroundStyle(Theme.secondary)
            }
            Spacer()
            if locked {
                Label("Needs access", systemImage: "lock.fill")
                    .font(Theme.label)
                    .foregroundStyle(Theme.tertiary)
            } else if let size = cleaner.sizes[category.id] {
                Text(size.bytes)
                    .font(Theme.number(13, .medium))
                    .foregroundStyle(Theme.secondary)
            } else {
                ProgressView().controlSize(.mini)
            }
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(Theme.accent)
                .disabled(locked)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .opacity(locked ? 0.6 : 1)
        .hoverLift()
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
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(Theme.ink.opacity(0.07), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress.value)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .opacity(progress.value > 0 ? 1 : 0)
                Color.clear
                    .frame(width: 92, height: 92)
                    .glass(Circle(), tint: Theme.accent.opacity(0.25), interactive: true)
                    .overlay {
                        if busy {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 26, weight: .medium))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .scaleEffect(progress.value > 0 ? 0.94 : 1)
            }
            .frame(width: 116, height: 116)
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

            Text("Hold to clean").font(Theme.label).foregroundStyle(enabled ? Theme.secondary : Theme.tertiary)
        }
        .opacity(enabled || busy ? 1 : 0.5)
    }
}

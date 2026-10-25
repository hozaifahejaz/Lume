import SwiftUI

struct CleanView: View {
    @ObservedObject var cleaner: Cleaner

    var body: some View {
        VStack(spacing: 0) {
            Text(eyebrow).monoLabel(Theme.amber.opacity(0.85))

            Text(bigNumber)
                .font(Theme.serif(96).monospacedDigit())
                .foregroundStyle(Theme.bone)
                .shadow(color: Theme.amber.opacity(0.22), radius: 34)
                .contentTransition(.numericText(countsDown: true))
                .padding(.top, 18)

            Text(caption)
                .font(Theme.body)
                .foregroundStyle(Theme.boneDim)
                .padding(.top, 8)

            action.padding(.top, 44)

            VStack(spacing: 0) {
                Hairline()
                ForEach(cleaner.categories) { category in
                    row(category)
                    Hairline()
                }
            }
            .padding(.top, 64)

            if !cleaner.unreadable.isEmpty {
                Text("Some folders need Full Disk Access · System Settings › Privacy & Security")
                    .monoLabel(size: 9.5)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.smooth(duration: 0.6), value: cleaner.phase)
        .animation(.smooth(duration: 0.6), value: cleaner.selectedTotal)
        .task { if cleaner.phase == .idle { await cleaner.scan() } }
    }

    private var eyebrow: String {
        switch cleaner.phase {
        case .idle, .scanning: return "Measuring"
        case .cleaning: return "Releasing"
        case .done: return "Released"
        case .ready: return "Reclaimable"
        }
    }

    private var caption: String {
        switch cleaner.phase {
        case .done: return "Your Mac rebuilds what it needs, when it needs it."
        default: return "Files your Mac and apps can safely rebuild."
        }
    }

    private var bigNumber: String {
        if case .done(let freed) = cleaner.phase { return freed.bytes }
        return cleaner.selectedTotal.bytes
    }

    @ViewBuilder private var action: some View {
        switch cleaner.phase {
        case .done:
            Button("Measure again") { Task { await cleaner.scan() } }
                .buttonStyle(MonoButtonStyle())
                .frame(height: 132)
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
        let isOn = cleaner.selected.contains(category.id) && !locked
        let toggle = {
            guard !locked else { return }
            if isOn { cleaner.selected.remove(category.id) } else { cleaner.selected.insert(category.id) }
        }
        return HStack(spacing: 16) {
            GlowToggle(isOn: isOn, disabled: locked, action: toggle)
            VStack(alignment: .leading, spacing: 4) {
                Text(category.name)
                    .font(Theme.serif(19, .regular))
                    .foregroundStyle(Theme.bone.opacity(isOn ? 1 : 0.7))
                Text(category.detail)
                    .font(Theme.body)
                    .foregroundStyle(Theme.boneDim)
            }
            Spacer()
            if locked {
                Text("Needs access").monoLabel(size: 9.5)
            } else if let size = cleaner.sizes[category.id] {
                Text(size.bytes)
                    .font(Theme.mono(12))
                    .foregroundStyle(isOn ? Theme.bone : Theme.boneDim)
            } else {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
    }
}

/// Press and hold for 1.2s to fill the ring and fire; releasing early cancels.
private struct HoldButton: View {
    let enabled: Bool
    let busy: Bool
    let onComplete: () -> Void
    @StateObject private var progress = ViewState<Double>(0)
    private let duration = 1.2

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().stroke(Theme.hairline, lineWidth: 1.5)
                Circle()
                    .trim(from: 0, to: progress.value)
                    .stroke(Theme.amber, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Theme.amber.opacity(0.9), radius: 10)
                    .opacity(progress.value > 0 ? 1 : 0)
                Circle()
                    .fill(RadialGradient(
                        colors: [Theme.amber.opacity(0.3 + 0.45 * progress.value), Theme.amber.opacity(0.04)],
                        center: .center, startRadius: 0, endRadius: 44
                    ))
                    .padding(12)
                    .shadow(color: Theme.amber.opacity(0.25 + 0.5 * progress.value), radius: 28)
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "sparkle")
                        .font(.system(size: 22, weight: .ultraLight))
                        .foregroundStyle(Theme.bone)
                }
            }
            .frame(width: 96, height: 96)
            .scaleEffect(progress.value > 0 ? 0.95 : 1)
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
                    withAnimation(.smooth(duration: 0.35)) { progress.value = 0 }
                }
            }
            .allowsHitTesting(enabled)

            Text("Hold to release").monoLabel(Theme.bone.opacity(enabled ? 0.75 : 0.3))
        }
        .opacity(enabled || busy ? 1 : 0.45)
    }
}

import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case clean = "Clean"
    case storage = "Storage"
    case startup = "Startup"

    var id: String { rawValue }
}

struct RootView: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @StateObject private var sectionState = ViewState<Page>(.overview)
    @StateObject private var cleaner = Cleaner()
    @StateObject private var storage = StorageScanner()
    @StateObject private var startup = StartupItems()
    @StateObject private var processes = ProcessList()
    @Namespace private var tabs

    var body: some View {
        ZStack(alignment: .bottom) {
            Backdrop(glow: Theme.tint(for: monitor.load), intensity: 0.6 + 0.8 * monitor.load)

            ZStack {
                page(sectionState.value)
                    .id(sectionState.value)
                    .transition(.blurFade)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Content dissolves into the ink before it reaches the floating tab bar.
            LinearGradient(colors: [Theme.ink.opacity(0), Theme.ink.opacity(0.92)], startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
                .allowsHitTesting(false)

            TabBar(selection: $sectionState.value, namespace: tabs)
                .padding(.bottom, 24)
        }
        .preferredColorScheme(.dark)
        .animation(.smooth(duration: 0.45), value: sectionState.value)
    }

    private func page(_ page: Page) -> some View {
        ScrollView {
            Group {
                switch page {
                case .overview: OverviewView(processes: processes, goTo: { sectionState.value = $0 })
                case .clean: CleanView(cleaner: cleaner)
                case .storage: StorageView(scanner: storage)
                case .startup: StartupView(items: startup)
                }
            }
            .frame(maxWidth: Theme.column)
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 64)
            .padding(.bottom, 130)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }
}

/// A floating glass pill with mono words and a glowing dot under the active one.
private struct TabBar: View {
    @Binding var selection: Page
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(Page.allCases.enumerated()), id: \.element) { index, page in
                Button { selection = page } label: {
                    VStack(spacing: 7) {
                        Text(page.rawValue)
                            .monoLabel(selection == page ? Theme.bone : Theme.boneDim, size: 10.5)
                        ZStack {
                            if selection == page {
                                Circle()
                                    .fill(Theme.amber)
                                    .frame(width: 4, height: 4)
                                    .shadow(color: Theme.amber, radius: 4)
                                    .shadow(color: Theme.amber.opacity(0.6), radius: 10)
                                    .matchedGeometryEffect(id: "dot", in: namespace)
                            }
                        }
                        .frame(height: 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 13)
                    .padding(.bottom, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        .padding(.horizontal, 8)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.55), radius: 30, y: 12)
        .animation(.smooth(duration: 0.4), value: selection)
    }
}

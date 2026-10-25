import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case clean = "Clean"
    case storage = "Storage"
    case startup = "Startup"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.33percent"
        case .clean: return "sparkles"
        case .storage: return "internaldrive"
        case .startup: return "power"
        }
    }
}

struct RootView: View {
    @StateObject private var sectionState = ViewState<Page>(.overview)
    @StateObject private var cleaner = Cleaner()
    @StateObject private var storage = StorageScanner()
    @StateObject private var startup = StartupItems()
    @StateObject private var processes = ProcessList()
    @Namespace private var tabs

    var body: some View {
        ZStack(alignment: .bottom) {
            Backdrop()

            // Every page is a fixed layout that fills the space between the title bar and the tab bar.
            ZStack {
                page(sectionState.value)
                    .id(sectionState.value)
                    .transition(.opacity)
            }
            .frame(maxWidth: 1120, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, Theme.margin)
            .padding(.top, 48)
            .padding(.bottom, 88)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TabBar(selection: $sectionState.value, namespace: tabs)
                .padding(.bottom, 24)
        }
        .preferredColorScheme(.light)
        .animation(.easeInOut(duration: 0.22), value: sectionState.value)
    }

    @ViewBuilder
    private func page(_ page: Page) -> some View {
        switch page {
        case .overview: OverviewView(processes: processes, goTo: { sectionState.value = $0 })
        case .clean: CleanView(cleaner: cleaner)
        case .storage: StorageView(scanner: storage)
        case .startup: StartupView(items: startup)
        }
    }
}

/// A floating glass capsule; the selected tab carries a tinted highlight that glides between tabs.
private struct TabBar: View {
    @Binding var selection: Page
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(Page.allCases.enumerated()), id: \.element) { index, page in
                let selected = selection == page
                Button { selection = page } label: {
                    HStack(spacing: 8) {
                        Image(systemName: page.symbol)
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 18)
                        Text(page.rawValue).font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(selected ? Theme.accent : Theme.secondary)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background {
                        if selected {
                            Capsule()
                                .fill(Theme.accent.opacity(0.12))
                                .matchedGeometryEffect(id: "selection", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        .padding(4)
        .glass(Capsule(), interactive: true)
                .animation(.spring(response: 0.4, dampingFraction: 0.82), value: selection)
    }
}

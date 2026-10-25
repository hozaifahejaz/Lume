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

            ZStack {
                page(sectionState.value)
                    .id(sectionState.value)
                    .transition(.liftFade)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TabBar(selection: $sectionState.value, namespace: tabs)
                .padding(.bottom, 22)
        }
        .preferredColorScheme(.light)
        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: sectionState.value)
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
            .padding(.top, 52)
            .padding(.bottom, 120)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }
}

/// A floating glass capsule; the selected tab carries a tinted highlight that glides between tabs.
private struct TabBar: View {
    @Binding var selection: Page
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(Page.allCases.enumerated()), id: \.element) { index, page in
                let selected = selection == page
                Button { selection = page } label: {
                    HStack(spacing: 7) {
                        Image(systemName: page.symbol).font(.system(size: 13, weight: .semibold))
                        Text(page.rawValue).font(Theme.rounded(13, .semibold))
                    }
                    .foregroundStyle(selected ? Theme.accent : Theme.ink.opacity(0.72))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background {
                        if selected {
                            Capsule()
                                .fill(Theme.accent.opacity(0.14))
                                .matchedGeometryEffect(id: "selection", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        .padding(6)
        .glass(Capsule(), interactive: true)
        .shadow(color: .black.opacity(0.08), radius: 22, y: 10)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: selection)
    }
}

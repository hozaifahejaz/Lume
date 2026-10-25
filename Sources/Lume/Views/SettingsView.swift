import SwiftUI
import ServiceManagement

/// Two choices, laid out like System Settings: whether Lume opens at login, and what the menu bar shows.
struct SettingsView: View {
    @AppStorage(MenuBarMeter.showsCPUKey) private var showsCPU = false
    @StateObject private var login = LoginItem()

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(get: { login.isEnabled }, set: { login.set($0) }))
                    .disabled(!login.isAvailable)
                if let note = login.note {
                    Text(note)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.secondary)
                }
            }
            Section {
                Picker("Menu bar shows", selection: $showsCPU) {
                    Text("Icon").tag(false)
                    Text("Icon and processor %").tag(true)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .preferredColorScheme(.light)
        .onAppear { login.refresh() }
    }
}

/// Lume's own login item through SMAppService, with a plain explanation when it can't be changed.
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var note: String?

    /// Only a real app bundle can register itself; `swift run` can't.
    let isAvailable = Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")

    func refresh() {
        guard isAvailable else {
            note = "Available when Lume runs as an app from the Applications folder."
            return
        }
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        note = status == .requiresApproval ? "Waiting for your approval in System Settings › General › Login Items." : nil
    }

    func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            refresh()
        } catch {
            refresh()
            note = "Couldn’t change this: \(error.localizedDescription)"
        }
    }
}

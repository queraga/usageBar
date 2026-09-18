import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    @StateObject private var loginItem = LaunchAtLoginSettings()
    @AppStorage("menuBarMetric") private var selection = MenuMetric.week.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Show in menu bar:").font(.caption).foregroundStyle(.secondary)
            Picker("Show in menu bar", selection: $selection) {
                ForEach(MenuMetric.allCases, id: \.rawValue) { metric in
                    Text(metric.title).tag(metric.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Toggle("Launch at login", isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.setEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            if loginItem.requiresApproval {
                Text("Allow UsageBar in macOS Login Items to finish enabling startup.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open Login Items…") {
                    SMAppService.openSystemSettingsLoginItems()
                }
                .controlSize(.small)
            }
            if let error = loginItem.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear { loginItem.refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refreshStatus()
        }
    }
}

@MainActor
private final class LaunchAtLoginSettings: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var errorMessage: String?

    func refreshStatus() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        requiresApproval = status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            errorMessage = "Could not change launch at login. Check macOS Login Items and try again."
        }
        refreshStatus()
    }
}

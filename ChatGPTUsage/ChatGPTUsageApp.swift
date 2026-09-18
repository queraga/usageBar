import SwiftUI
import AppKit
import OSLog

@MainActor
final class UsageAppDelegate: NSObject, NSApplicationDelegate {
    let store = UsageStore(provider: CodexUsageProvider())

    func applicationDidFinishLaunching(_ notification: Notification) {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let system = "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        // The menu bar item is the only UI, so record that launch got this far: a running app
        // with no visible item means macOS had no room for it, not that launch failed.
        AppLog.app.log("Launched \(version, privacy: .public) (\(build, privacy: .public)) on \(system, privacy: .public)")
        AppLog.terminal("""
            UsageBar \(version) (\(build)) · \(system) · pid \(ProcessInfo.processInfo.processIdentifier)
            Running. There is no window: look for "Week —" in the menu bar until usage loads.
            Diagnostics go to the unified log, not here:
              /usr/bin/log stream --level debug --predicate 'subsystem == "\(AppLog.subsystem)"'
            """)
        store.startAutomaticRefresh()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppLog.app.log("Terminating")
        Task {
            await store.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct ChatGPTUsageApp: App {
    @NSApplicationDelegateAdaptor(UsageAppDelegate.self) private var delegate
    @AppStorage("menuBarMetric") private var selection = MenuMetric.week.rawValue

    var body: some Scene {
        MenuBarExtra {
            UsagePopover(store: delegate.store)
        } label: {
            UsageMenuLabel(store: delegate.store, selection: MenuMetric(rawValue: selection) ?? .week)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct UsageMenuLabel: View {
    @ObservedObject var store: UsageStore
    let selection: MenuMetric
    var body: some View {
        MenuBarLabel(snapshot: store.snapshot, selection: selection)
    }
}

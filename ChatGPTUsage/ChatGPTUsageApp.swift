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
        // --check is for exactly this: report whether the setup works, then exit. The menu bar
        // app itself never exits on a failed refresh, since most failures are transient.
        if CommandLine.arguments.contains("--check") {
            Task { await Self.check() }
            return
        }
        Task { await startup() }
    }

    /// The first refresh decides whether there is anything to run: a broken or missing codex
    /// cannot be fixed by retrying, so report it and exit rather than sit in the menu bar
    /// showing a dash forever. Recoverable failures keep the app alive to retry.
    private func startup() async {
        await store.refresh()
        if let failure = store.lastFailure, failure.isSetupFailure {
            AppLog.app.error("Exiting on startup failure: \(failure.logLabel, privacy: .public)")
            Self.report(failure)
            await store.shutdown()
            exit(1)
        }
        store.startAutomaticRefresh(refreshNow: false)
    }

    private static func check() async {
        let provider = CodexUsageProvider()
        var status: Int32 = 0
        var resolved: String?
        do {
            let path = try CodexExecutableResolver.resolve().path
            resolved = path
            AppLog.write("codex: \(path)")
            let snapshot = try await provider.fetchUsage()
            let five = Int(snapshot.fiveHour.remainingPercent.rounded())
            let week = Int(snapshot.weekly.remainingPercent.rounded())
            AppLog.write("ok: 5h \(five)% remaining, week \(week)% remaining")
        } catch {
            report(error, resolved: resolved)
            status = 1
        }
        await provider.shutdown()
        exit(status)
    }

    private static func report(_ error: Error, resolved: String? = nil) {
        let reason = (error as? UsageProviderError)?.errorDescription ?? error.localizedDescription
        AppLog.write("error: \(reason) [\(error.logLabel)]")
        if let path = resolved ?? (try? CodexExecutableResolver.resolve().path) {
            AppLog.write("hint: `\(path) --version` must print a version for UsageBar to work")
        } else {
            AppLog.write("hint: install the ChatGPT app or the codex CLI, then try again")
        }
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

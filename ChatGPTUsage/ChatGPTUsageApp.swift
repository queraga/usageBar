import SwiftUI
import AppKit

@MainActor
final class UsageAppDelegate: NSObject, NSApplicationDelegate {
    let store = UsageStore(provider: CodexUsageProvider())

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.startAutomaticRefresh()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
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

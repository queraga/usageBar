import SwiftUI
import OSLog

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    private(set) var lastFailure: UsageProviderError?
    private var refreshLoop: Task<Void, Never>?
    private var isStopped = false
    private var isFirstRefresh = true
    private let provider: any UsageProvider

    init(provider: any UsageProvider) { self.provider = provider }

    func startAutomaticRefresh(interval: UInt64 = 300_000_000_000, refreshNow: Bool = true) {
        guard refreshLoop == nil, !isStopped else { return }
        AppLog.store.log("Refreshing every \(Double(interval) / 1_000_000_000, format: .fixed(precision: 1), privacy: .public)s")
        refreshLoop = Task { [weak self] in
            if refreshNow { await self?.refresh() }
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: interval) } catch { break }
                await self?.refresh()
            }
        }
    }

    func shutdown() async {
        isStopped = true
        refreshLoop?.cancel()
        refreshLoop = nil
        await provider.shutdown()
    }

    func refreshIfNeeded() async {
        if snapshot == nil { await refresh() }
    }

    func refresh() async {
        guard !isRefreshing, !isStopped else {
            AppLog.store.debug("Refresh skipped (refreshing: \(self.isRefreshing, privacy: .public), stopped: \(self.isStopped, privacy: .public))")
            return
        }
        isRefreshing = true
        // The startup refresh is reported by its caller, which also decides whether to exit.
        let isStartupRefresh = isFirstRefresh
        isFirstRefresh = false
        defer { isRefreshing = false }
        do {
            snapshot = try await provider.fetchUsage()
            errorMessage = nil
            lastFailure = nil
            AppLog.store.debug("Snapshot updated")
        } catch {
            let message = (error as? UsageProviderError)?.errorDescription ?? "Could not refresh usage. Try again."
            errorMessage = snapshot == nil ? "Usage unavailable. \(message)" : "Data may be stale. \(message)"
            lastFailure = error as? UsageProviderError
            AppLog.store.error("Refresh failed on \(error.logLabel, privacy: .public), showing \(self.snapshot == nil ? "no data" : "stale data", privacy: .public)")
            // Without this the popover is the only place the reason appears, and the popover
            // is unreachable when the menu bar has no room for the item.
            if !isStartupRefresh { AppLog.terminal("error: \(message) [\(error.logLabel)]") }
        }
    }
}

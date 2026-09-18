import SwiftUI
import OSLog

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    private var refreshLoop: Task<Void, Never>?
    private var isStopped = false
    private let provider: any UsageProvider

    init(provider: any UsageProvider) { self.provider = provider }

    func startAutomaticRefresh(interval: UInt64 = 300_000_000_000) {
        guard refreshLoop == nil, !isStopped else { return }
        AppLog.store.log("Refreshing every \(Double(interval) / 1_000_000_000, format: .fixed(precision: 1), privacy: .public)s")
        refreshLoop = Task { [weak self] in
            await self?.refresh()
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
        defer { isRefreshing = false }
        do {
            snapshot = try await provider.fetchUsage()
            errorMessage = nil
            AppLog.store.debug("Snapshot updated")
        } catch {
            let message = (error as? UsageProviderError)?.errorDescription ?? "Could not refresh usage. Try again."
            errorMessage = snapshot == nil ? "Usage unavailable. \(message)" : "Data may be stale. \(message)"
            AppLog.store.error("Refresh failed on \(error.logLabel, privacy: .public), showing \(self.snapshot == nil ? "no data" : "stale data", privacy: .public)")
        }
    }
}

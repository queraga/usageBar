import Foundation

struct MockUsageProvider: UsageProvider {
    private let fiveHourReset = Date().addingTimeInterval(90 * 60)
    private let weeklyReset = Date().addingTimeInterval(3 * 24 * 60 * 60)

    func fetchUsage() async throws -> UsageSnapshot {
        UsageSnapshot(
            fiveHour: UsageMetric(usedPercent: 38, resetAt: fiveHourReset),
            weekly: UsageMetric(usedPercent: 67, resetAt: weeklyReset),
            updatedAt: Date()
        )
    }
}

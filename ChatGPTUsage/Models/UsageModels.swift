import Foundation

struct UsageMetric: Sendable {
    let usedPercent: Double
    let resetAt: Date?

    init(usedPercent: Double, resetAt: Date?) {
        self.usedPercent = usedPercent.isFinite ? min(100, max(0, usedPercent)) : 0
        self.resetAt = resetAt
    }

    var remainingPercent: Double { 100 - usedPercent }
}

struct UsageSnapshot: Sendable {
    let fiveHour: UsageMetric
    let weekly: UsageMetric
    let updatedAt: Date
}

enum MenuMetric: String, CaseIterable {
    case week, fiveHour
    var title: String { self == .week ? "Week" : "5h" }
    func metric(in snapshot: UsageSnapshot) -> UsageMetric {
        self == .week ? snapshot.weekly : snapshot.fiveHour
    }
}

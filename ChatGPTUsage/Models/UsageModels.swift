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

/// Either window may be absent: accounts report only the limits that currently apply, so a
/// plan with no active 5-hour window still has a usable weekly one.
struct UsageSnapshot: Sendable {
    let fiveHour: UsageMetric?
    let weekly: UsageMetric?
    let updatedAt: Date

    init(fiveHour: UsageMetric?, weekly: UsageMetric?, updatedAt: Date) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.updatedAt = updatedAt
    }
}

enum MenuMetric: String, CaseIterable {
    case week, fiveHour
    var title: String { self == .week ? "Week" : "5h" }
    var other: MenuMetric { self == .week ? .fiveHour : .week }

    func metric(in snapshot: UsageSnapshot) -> UsageMetric? {
        self == .week ? snapshot.weekly : snapshot.fiveHour
    }

    /// The chosen window, or whichever one the account does report.
    func availableMetric(in snapshot: UsageSnapshot) -> (metric: UsageMetric, shown: MenuMetric)? {
        if let metric = metric(in: snapshot) { return (metric, self) }
        if let fallback = other.metric(in: snapshot) { return (fallback, other) }
        return nil
    }
}

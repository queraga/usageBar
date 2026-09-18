import SwiftUI

struct MenuBarLabel: View {
    let snapshot: UsageSnapshot?
    let selection: MenuMetric

    var body: some View {
        if let snapshot {
            let metric = selection.metric(in: snapshot)
            // Native colored dot avoids relying on menu bar text foreground colors.
            Text("\(indicator(metric.usedPercent)) \(selection.title) \(Int(metric.remainingPercent.rounded()))%")
                .accessibilityLabel("\(selection.title), \(Int(metric.remainingPercent.rounded())) percent remaining")
        } else {
            Text("\(selection.title) —")
        }
    }

    private func indicator(_ used: Double) -> String {
        used >= 85 ? "🔴" : used >= 60 ? "🟡" : "🟢"
    }
}

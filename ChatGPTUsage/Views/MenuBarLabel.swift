import SwiftUI

struct MenuBarLabel: View {
    let snapshot: UsageSnapshot?
    let selection: MenuMetric

    var body: some View {
        // Falls back to the other window when the account does not report the chosen one.
        if let snapshot, let available = selection.availableMetric(in: snapshot) {
            let remaining = Int(available.metric.remainingPercent.rounded())
            // Native colored dot avoids relying on menu bar text foreground colors.
            Text("\(indicator(available.metric.usedPercent)) \(available.shown.title) \(remaining)%")
                .accessibilityLabel("\(available.shown.title), \(remaining) percent remaining")
        } else {
            Text("\(selection.title) —")
        }
    }

    private func indicator(_ used: Double) -> String {
        used >= 85 ? "🔴" : used >= 60 ? "🟡" : "🟢"
    }
}

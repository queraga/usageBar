import SwiftUI

/// Shown when the account does not report that window at all, which is not an error.
struct UnavailableRow: View {
    let title: String

    var body: some View {
        HStack {
            Text(title).fontWeight(.medium).foregroundStyle(.secondary)
            Spacer()
            Text("not reported").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct UsageRow: View {
    let title: String
    let metric: UsageMetric

    private var statusColor: Color {
        metric.usedPercent >= 85 ? .red : metric.usedPercent >= 60 ? .yellow : .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).fontWeight(.medium)
                Spacer()
                Text("\(Int(metric.remainingPercent.rounded()))% left").monospacedDigit()
            }
            ProgressView(value: metric.remainingPercent, total: 100)
                .tint(statusColor)
                .accessibilityLabel("\(title), remaining usage")
                .accessibilityValue("\(Int(metric.remainingPercent.rounded())) percent")
            if let reset = metric.resetAt {
                Text("Resets \(reset.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Reset time unavailable").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

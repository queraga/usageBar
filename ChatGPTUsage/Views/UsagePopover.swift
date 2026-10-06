import SwiftUI
import AppKit

struct UsagePopover: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("UsageBar").font(.headline)
                Spacer()
            }
            if let snapshot = store.snapshot {
                if let fiveHour = snapshot.fiveHour {
                    UsageRow(title: "5h limit", metric: fiveHour)
                } else {
                    UnavailableRow(title: "5h limit")
                }
                if let weekly = snapshot.weekly {
                    UsageRow(title: "Week limit", metric: weekly)
                } else {
                    UnavailableRow(title: "Week limit")
                }
                Text("Last updated: \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            } else if store.isRefreshing {
                ProgressView("Loading usage…").controlSize(.small)
            }
            if let message = store.errorMessage {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            Divider()
            DisclosureGroup("Settings") {
                SettingsView().padding(.top, 8)
            }
            HStack {
                Button(store.isRefreshing ? "Refreshing…" : "Refresh") {
                    Task { await store.refresh() }
                }
                .disabled(store.isRefreshing)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 300)
        .task { await store.refreshIfNeeded() }
    }
}

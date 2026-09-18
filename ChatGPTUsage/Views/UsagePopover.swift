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
                UsageRow(title: "5h limit", metric: snapshot.fiveHour)
                UsageRow(title: "Week limit", metric: snapshot.weekly)
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

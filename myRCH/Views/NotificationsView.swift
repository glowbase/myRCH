import SwiftUI

/// Inbox of notifications — new results, messages and appointment reminders.
struct NotificationsView: View {
    let patientID: String
    @Environment(Session.self) private var session

    var body: some View {
        AsyncSection {
            try await load()
        } content: { items in
            List {
                if items.isEmpty {
                    ContentUnavailableView("You're all caught up",
                                           systemImage: "checkmark.circle",
                                           description: Text("New updates will appear here."))
                } else {
                    ForEach(items) { NotificationRow(item: $0) }
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async throws -> [NotificationItem] {
        async let messages = try? session.service.messages(for: patientID)
        async let results = try? session.service.testResults(for: patientID)

        var items: [NotificationItem] = []
        for m in await messages ?? [] {
            items.append(NotificationItem(
                id: "msg-\(m.id)", icon: "envelope.fill", tint: Theme.brand,
                title: m.subject, detail: "Message from \(m.sender)",
                date: m.date, isUnread: m.isUnread))
        }
        for r in (await results ?? []).prefix(5) {
            items.append(NotificationItem(
                id: "res-\(r.id)", icon: "testtube.2", tint: Theme.green,
                title: r.name, detail: "New test result available",
                date: r.date, isUnread: r.isUnread))
        }
        return items.sorted { $0.date > $1.date }
    }
}

struct NotificationItem: Identifiable {
    let id: String
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let date: Date
    let isUnread: Bool
}

private struct NotificationRow: View {
    let item: NotificationItem

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.icon)
                .foregroundStyle(item.tint)
                .frame(width: 40, height: 40)
                .background(item.tint.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(item.isUnread ? .semibold : .regular))
                    .lineLimit(1)
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(item.date.mediumDate)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if item.isUnread {
                Circle().fill(Theme.brand).frame(width: 9, height: 9)
            }
        }
        .padding(.vertical, 4)
    }
}

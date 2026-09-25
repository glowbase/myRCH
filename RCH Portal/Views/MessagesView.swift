import SwiftUI

struct MessagesView: View {
    let patientID: String
    @Environment(Session.self) private var session

    var body: some View {
        AsyncSection {
            try await session.service.messages(for: patientID)
        } content: { messages in
            List {
                ForEach(messages) { message in
                    NavigationLink {
                        MessageDetailView(message: message)
                    } label: {
                        MessageRow(message: message)
                    }
                }
            }
            .overlay {
                if messages.isEmpty {
                    ContentUnavailableView("No messages", systemImage: "envelope",
                                           description: Text("Messages from your care team will appear here."))
                }
            }
        }
        .navigationTitle("Messages")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New", systemImage: "square.and.pencil") {}
            }
        }
    }
}

struct MessageRow: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(message.isUnread ? Theme.brand : .clear)
                .frame(width: 10, height: 10)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(message.sender)
                        .font(.subheadline.weight(message.isUnread ? .semibold : .regular))
                    Spacer()
                    Text(message.date.mediumDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(message.subject)
                    .font(.headline)
                    .fontWeight(message.isUnread ? .semibold : .regular)
                Text(message.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct MessageDetailView: View {
    let message: Message

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(message.subject).font(.title2.bold())
                HStack {
                    AvatarView(initials: String(message.sender.prefix(1)))
                    VStack(alignment: .leading) {
                        Text(message.sender).font(.subheadline.weight(.medium))
                        Text(message.date.dateAndTime)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                Text(message.preview)
                Text("The full message body would be shown here when connected to a live backend.")
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Message")
        .navigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI

// MARK: - Conversation list

struct MessagesView: View {
    let patientID: String
    @Environment(Session.self) private var session

    @State private var conversations: [Conversation] = []
    @State private var careTeam: [CareTeamMember] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var showsNewMessage = false

    var body: some View {
        Group {
            if isLoading {
                SkeletonList()
            } else {
                list
            }
        }
        .navigationTitle("Messages")
        .searchable(text: $searchText, prompt: "Search conversations")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New message", systemImage: "square.and.pencil") {
                    showsNewMessage = true
                }
            }
        }
        .sheet(isPresented: $showsNewMessage) {
            NewMessageSheet(careTeam: careTeam) { conversation in
                conversations.insert(conversation, at: 0)
            }
        }
        .task { await load() }
    }

    private var list: some View {
        List {
            Section {
                ForEach($conversations) { $conversation in
                    if matches(conversation) {
                        NavigationLink {
                            ConversationDetailView(conversation: $conversation)
                        } label: {
                            ConversationRow(conversation: conversation)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                conversation.isUnread.toggle()
                            } label: {
                                Label(conversation.isUnread ? "Read" : "Unread",
                                      systemImage: conversation.isUnread ? "envelope.open" : "envelope.badge")
                            }
                            .tint(Theme.brand)
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                conversation.isBookmarked.toggle()
                            } label: {
                                Label("Bookmark", systemImage: conversation.isBookmarked ? "bookmark.slash" : "bookmark")
                            }
                            .tint(Theme.orange)
                        }
                    }
                }
            } footer: {
                if visibleCount > 0 {
                    Text("Showing \(visibleCount) of \(conversations.count) conversations")
                }
            }
        }
        .overlay {
            if visibleCount == 0 {
                if searchText.isEmpty {
                    ContentUnavailableView {
                        Label("No messages", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("Start a conversation with your child's care team.")
                    } actions: {
                        Button("New message") { showsNewMessage = true }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.brand)
                    }
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    private var visibleCount: Int {
        conversations.filter(matches).count
    }

    private func matches(_ conversation: Conversation) -> Bool {
        guard !searchText.isEmpty else { return true }
        return conversation.subject.localizedCaseInsensitiveContains(searchText)
            || conversation.participants.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
            || conversation.messages.contains { $0.body.localizedCaseInsensitiveContains(searchText) }
    }

    private func load() async {
        isLoading = true
        async let threads = try? session.service.conversations(for: patientID)
        async let team = try? session.service.careTeam(for: patientID)
        conversations = (await threads ?? []).sorted { $0.date > $1.date }
        careTeam = await team ?? []
        isLoading = false
    }
}

struct ConversationRow: View {
    let conversation: Conversation

    private var lastAuthor: String {
        guard let last = conversation.lastMessage else { return "" }
        return last.isFromMe ? "You" : last.authorName
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: conversation.participants.count > 1 ? "person.2.fill" : "person.fill")
                .font(.subheadline)
                .foregroundStyle(Theme.brand)
                .frame(width: 40, height: 40)
                .background(Theme.brand.opacity(0.12), in: .circle)
                .overlay(alignment: .topTrailing) {
                    if conversation.isUnread {
                        Circle()
                            .fill(Theme.brand)
                            .frame(width: 11, height: 11)
                            .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
                            .offset(x: 2, y: -2)
                    }
                }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(conversation.subject)
                        .font(.headline)
                        .fontWeight(conversation.isUnread ? .bold : .semibold)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(conversation.date.shortRelativeDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(lastAuthor)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink.opacity(0.8))
                Text(conversation.lastMessage?.body ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if conversation.isBookmarked {
                    Label("Bookmarked", systemImage: "bookmark.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Thread

struct ConversationDetailView: View {
    @Binding var conversation: Conversation

    @State private var reply = ""
    @State private var includeOthers = true
    @State private var showsParticipants = false
    @State private var showsDiscardConfirmation = false
    @FocusState private var composerFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    threadHeader
                    ForEach(conversation.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    if let viewed = conversation.lastViewedByStaff {
                        Label("Last viewed by staff \(viewed.dateAndTime)", systemImage: "eye")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 4)
                    }
                }
                .padding()
            }
            .onChange(of: conversation.messages.count) {
                withAnimation { proxy.scrollTo(conversation.messages.last?.id, anchor: .bottom) }
            }
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) { composer }
        .navigationTitle(conversation.subject)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(conversation.isBookmarked ? "Remove bookmark" : "Bookmark",
                           systemImage: conversation.isBookmarked ? "bookmark.slash" : "bookmark") {
                        conversation.isBookmarked.toggle()
                    }
                    Button("Mark as unread", systemImage: "envelope.badge") {
                        conversation.isUnread = true
                    }
                    Button("Participants", systemImage: "person.2") {
                        showsParticipants = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showsParticipants) {
            ParticipantsSheet(participants: conversation.participants)
        }
        .task { conversation.isUnread = false }
    }

    private var threadHeader: some View {
        Button { showsParticipants = true } label: {
            HStack(spacing: 12) {
                Image(systemName: conversation.participants.count > 1 ? "person.2.fill" : "person.fill")
                    .foregroundStyle(Theme.brand)
                    .frame(width: 40, height: 40)
                    .background(Theme.brand.opacity(0.12), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.participants.map(\.name).formatted(.list(type: .and)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(conversation.participants.first?.department ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                if composerFocused {
                    Toggle(isOn: $includeOthers) {
                        Text("Include everyone with access to this record")
                            .font(.caption)
                    }
                    .tint(Theme.brand)

                    Label("Call 000 in an emergency. Replies can take 2–3 business days.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.orange)
                }

                HStack(alignment: .bottom, spacing: 10) {
                    Button {
                    } label: {
                        Image(systemName: "paperclip")
                            .font(.title3)
                            .foregroundStyle(Theme.brand)
                            .frame(width: 38, height: 38)
                    }
                    .accessibilityLabel("Attach a file")

                    TextField("Write a reply…", text: $reply, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($composerFocused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color(.secondarySystemGroupedBackground), in: .capsule)
                        .overlay(Capsule().strokeBorder(Color.black.opacity(0.08)))

                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(canSend ? Theme.brand : Theme.brand.mix(with: .white, by: 0.55),
                                        in: .circle)
                    }
                    .disabled(!canSend)
                    .accessibilityLabel("Send reply")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .animation(.easeInOut(duration: 0.2), value: composerFocused)
    }

    private var canSend: Bool {
        !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        conversation.messages.append(
            ConversationMessage(id: UUID().uuidString, authorName: "You", authorRole: nil,
                                isFromMe: true, date: .now, body: text))
        reply = ""
        composerFocused = false
    }
}

// MARK: - Bubble

private struct MessageBubble: View {
    let message: ConversationMessage

    var body: some View {
        VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 6) {
            HStack(spacing: 8) {
                if message.isFromMe { Spacer(minLength: 0) }
                if !message.isFromMe {
                    AvatarView(initials: initials, tint: Theme.teal, size: 30)
                }
                VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 1) {
                    Text(message.isFromMe ? "You" : message.authorName)
                        .font(.subheadline.weight(.semibold))
                    Text(message.date.dateAndTime)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if message.isFromMe {
                    AvatarView(initials: "Me", tint: Theme.brand, size: 30)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(message.body)
                    .font(.subheadline)
                    .foregroundStyle(message.isFromMe ? .white : .primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(message.attachmentNames, id: \.self) { name in
                    Label(name, systemImage: "paperclip")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(message.isFromMe ? .white : Theme.brand)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background((message.isFromMe ? Color.white.opacity(0.2) : Theme.brand.opacity(0.12)),
                                    in: .capsule)
                }
            }
            .padding(14)
            .background {
                let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
                if message.isFromMe {
                    shape.fill(Theme.brand)
                } else {
                    shape.fill(Color(.secondarySystemGroupedBackground))
                }
            }
            .padding(message.isFromMe ? .leading : .trailing, 24)
        }
        .frame(maxWidth: .infinity, alignment: message.isFromMe ? .trailing : .leading)
        .accessibilityElement(children: .combine)
    }

    private var initials: String {
        message.authorName.split(separator: " ").prefix(2)
            .compactMap(\.first).map(String.init).joined()
    }
}

// MARK: - Participants

private struct ParticipantsSheet: View {
    let participants: [CareTeamMember]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Care team") {
                    ForEach(participants) { member in
                        HStack(spacing: 14) {
                            AvatarView(initials: member.initials, tint: Theme.teal, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.name).font(.headline)
                                Text(member.role)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(member.department)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Participants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - New message

private struct NewMessageSheet: View {
    let careTeam: [CareTeamMember]
    let onSend: (Conversation) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var recipientID: String?
    @State private var subject = ""
    @State private var body_ = ""
    @State private var includeOthers = true

    private var recipient: CareTeamMember? {
        careTeam.first { $0.id == recipientID }
    }

    private var canSend: Bool {
        recipient != nil
            && !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("To") {
                    Picker("Care team member", selection: $recipientID) {
                        Text("Choose someone").tag(String?.none)
                        ForEach(careTeam) { member in
                            Text("\(member.name) — \(member.role)").tag(Optional(member.id))
                        }
                    }
                    if let recipient {
                        LabeledContent("Department", value: recipient.department)
                    }
                    Toggle("Include everyone with access to this record", isOn: $includeOthers)
                        .tint(Theme.brand)
                }

                Section("Subject") {
                    TextField("What is this about?", text: $subject)
                }

                Section {
                    TextField("Write your message…", text: $body_, axis: .vertical)
                        .lineLimit(6...14)
                } header: {
                    Text("Message")
                } footer: {
                    Label("Call 000 in an emergency. Non-urgent messages are usually answered within 2–3 business days.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.orange)
                }
            }
            .navigationTitle("New message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { send() }.disabled(!canSend)
                }
            }
        }
    }

    private func send() {
        guard let recipient else { return }
        let message = ConversationMessage(
            id: UUID().uuidString, authorName: "You", authorRole: nil,
            isFromMe: true, date: .now,
            body: body_.trimmingCharacters(in: .whitespacesAndNewlines))
        onSend(Conversation(
            id: UUID().uuidString,
            subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
            participants: [recipient],
            messages: [message],
            isUnread: false))
        dismiss()
    }
}

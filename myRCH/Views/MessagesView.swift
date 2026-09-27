import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

extension Session {
    /// Starting a new conversation only works in demo mode for now: the
    /// portal's requests for it haven't been captured, and a message that
    /// looked sent but never reached the care team would be worse than no
    /// button. Flip this on once it's mapped. (Replies are mapped.)
    var canStartConversations: Bool { !useLivePortal }

    /// The conversation on the portal website, for actions the app can't do yet.
    func portalURL(forConversation id: String) -> URL? {
        var components = URLComponents(string: "https://\(MyChartConfig().host)\(MyChartConfig().basePath)/app/communication-center/conversation")
        components?.queryItems = [URLQueryItem(name: "id", value: id)]
        return components?.url
    }
}

// MARK: - Conversation list

struct MessagesView: View {
    let patientID: String
    @Environment(Session.self) private var session

    @State private var folder: MessageFolder = .inbox
    @State private var conversations: [Conversation] = []
    @State private var careTeam: [CareTeamMember] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var showsNewMessage = false
    /// Just moved to Trash, for the Undo bar.
    @State private var trashed: [Conversation] = []
    @State private var actionError: String?
    /// Select mode, for acting on several conversations at once.
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<Conversation.ID>()

    private var isSelecting: Bool { editMode.isEditing }

    var body: some View {
        Group {
            if isLoading {
                SkeletonList()
            } else {
                list
            }
        }
        // The inbox keeps the tab's name; other folders show theirs.
        .navigationTitle(folder == .inbox ? "Messages" : folder.title)
        .searchable(text: $searchText, prompt: "Search conversations")
        .toolbar { toolbar }
        .environment(\.editMode, $editMode)
        .sheet(isPresented: $showsNewMessage) {
            NewMessageSheet(careTeam: careTeam) { conversation in
                conversations.insert(conversation, at: 0)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                selectionBar
            } else if !trashed.isEmpty {
                undoBar
            }
        }
        .animation(.default, value: trashed.map(\.id))
        .animation(.default, value: isSelecting)
        .alert("Couldn't update the conversation", isPresented: .constant(actionError != nil)) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .task(id: folder) { await load() }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                let visible = Set(conversations.filter(matches).map(\.id))
                Button(selection.isSuperset(of: visible) && !visible.isEmpty ? "Deselect All" : "Select All") {
                    selection = selection.isSuperset(of: visible) ? [] : visible
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { endSelecting() }
                    .fontWeight(.semibold)
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Folder", selection: $folder) {
                        ForEach(MessageFolder.allCases) { folder in
                            Label(folder.title, systemImage: folder.systemImage).tag(folder)
                        }
                    }
                } label: {
                    Label("Folder", systemImage: folder == .inbox ? "tray" : "\(folder.systemImage).fill")
                }
            }
            if !conversations.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Select") {
                        trashed = []
                        editMode = .active
                    }
                }
            }
            if session.canStartConversations {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New message", systemImage: "square.and.pencil") {
                        showsNewMessage = true
                    }
                }
            }
        }
    }

    private var list: some View {
        List(selection: $selection) {
            Section {
                ForEach($conversations) { $conversation in
                    if matches(conversation) {
                        NavigationLink {
                            ConversationDetailView(
                                conversation: $conversation,
                                onBookmark: { id, on in Task { await setBookmarked([id], on) } },
                                onMarkUnread: { id in Task { await setUnread([id], true) } },
                                isInTrash: folder == .trash,
                                onTrash: { id in Task { await moveToTrash([id], afterDismissing: true) } },
                                onRestore: { id in Task { await restoreFromTrash([id], afterDismissing: true) } })
                        } label: {
                            ConversationRow(conversation: conversation)
                        }
                        .tag(conversation.id)
                        .swipeActions(edge: .leading) {
                            Button {
                                let id = conversation.id, unread = !conversation.isUnread
                                Task { await setUnread([id], unread) }
                            } label: {
                                Label(conversation.isUnread ? "Read" : "Unread",
                                      systemImage: conversation.isUnread ? "envelope.open" : "envelope.badge")
                            }
                            .tint(Theme.brand)
                        }
                        .swipeActions(edge: .trailing) {
                            if folder == .trash {
                                Button {
                                    let id = conversation.id
                                    Task { await restoreFromTrash([id]) }
                                } label: {
                                    Label("Unarchive", systemImage: "tray.and.arrow.up")
                                }
                                .tint(Theme.brand)
                            } else {
                                Button {
                                    let id = conversation.id
                                    Task { await moveToTrash([id]) }
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                                .tint(Theme.blue)
                                Button {
                                    let id = conversation.id, on = !conversation.isBookmarked
                                    Task { await setBookmarked([id], on) }
                                } label: {
                                    Label(conversation.isBookmarked ? "Remove Bookmark" : "Bookmark",
                                          systemImage: conversation.isBookmarked ? "bookmark.slash" : "bookmark")
                                }
                                .tint(Theme.orange)
                            }
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
                        Label(emptyTitle, systemImage: emptySymbol)
                    } description: {
                        Text(emptyDescription)
                    } actions: {
                        if session.canStartConversations && folder == .inbox {
                            Button("New message") { showsNewMessage = true }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.brand)
                        }
                    }
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    private var emptyTitle: String {
        switch folder {
        case .inbox: "No messages"
        case .bookmarked: "No bookmarks"
        case .trash: "No archived messages"
        }
    }

    private var emptySymbol: String {
        switch folder {
        case .inbox: "bubble.left.and.bubble.right"
        case .bookmarked: "bookmark"
        case .trash: "archivebox"
        }
    }

    private var emptyDescription: String {
        switch folder {
        case .inbox: "Start a conversation with your child's care team."
        case .bookmarked: "Bookmark a conversation to keep it here."
        case .trash: "Conversations you archive appear here."
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

    // MARK: Bars

    /// Actions for the selected conversations. Read and bookmark flip to
    /// their opposites when every selected conversation already has them.
    private var selectionBar: some View {
        let selected = conversations.filter { selection.contains($0.id) }
        let ids = selected.map(\.id)
        let anyUnread = selected.contains(where: \.isUnread)
        let allBookmarked = !selected.isEmpty && selected.allSatisfy(\.isBookmarked)

        return HStack {
            if folder == .trash {
                barButton("Unarchive", systemImage: "tray.and.arrow.up") {
                    Task { await restoreFromTrash(ids); endSelecting() }
                }
            } else {
                barButton(anyUnread ? "Read" : "Unread",
                          systemImage: anyUnread ? "envelope.open" : "envelope.badge") {
                    Task { await setUnread(ids, !anyUnread); endSelecting() }
                }
                Spacer()
                barButton(allBookmarked ? "Remove Bookmark" : "Bookmark",
                          systemImage: allBookmarked ? "bookmark.slash" : "bookmark") {
                    Task { await setBookmarked(ids, !allBookmarked); endSelecting() }
                }
                Spacer()
                barButton("Archive", systemImage: "archivebox") {
                    Task { await moveToTrash(ids); endSelecting() }
                }
            }
        }
        .disabled(selected.isEmpty)
        .padding(.horizontal, 28)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func barButton(_ title: String, systemImage: String, tint: Color = Theme.brand,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.caption2)
            }
        }
        .tint(tint)
    }

    private var undoBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "archivebox")
                .foregroundStyle(.secondary)
            Text(trashed.count == 1 ? "Archived" : "Archived \(trashed.count) conversations")
                .font(.subheadline)
            Spacer(minLength: 8)
            Button("Undo") {
                Task { await undoTrash() }
            }
            .font(.subheadline.weight(.semibold))
            .tint(Theme.brand)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: .capsule)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        // Offer Undo for a few seconds; restarts if more are trashed.
        .task(id: trashed.map(\.id)) {
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { trashed = [] }
        }
    }

    private func endSelecting() {
        selection = []
        editMode = .inactive
    }

    // MARK: Actions

    /// Rows update straight away, and go back if the portal refuses. In
    /// Bookmarked, an unbookmarked row stays until the next load, so an open
    /// thread's binding never points at a removed row.
    private func setBookmarked(_ ids: [String], _ on: Bool) async {
        await update(ids, \.isBookmarked, to: on) {
            try await session.service.setConversationsBookmarked(on, ids: ids, for: patientID)
        }
    }

    private func setUnread(_ ids: [String], _ unread: Bool) async {
        await update(ids, \.isUnread, to: unread) {
            try await session.service.setConversationsUnread(unread, ids: ids, for: patientID)
        }
    }

    private func update(_ ids: [String], _ flag: WritableKeyPath<Conversation, Bool>, to value: Bool,
                        _ send: () async throws -> Void) async {
        let previous = Dictionary(uniqueKeysWithValues: conversations.filter { ids.contains($0.id) }
            .map { ($0.id, $0[keyPath: flag]) })
        for index in conversations.indices where ids.contains(conversations[index].id) {
            conversations[index][keyPath: flag] = value
        }
        do {
            try await send()
        } catch {
            for index in conversations.indices {
                if let was = previous[conversations[index].id] { conversations[index][keyPath: flag] = was }
            }
            actionError = error.localizedDescription
        }
    }

    private func moveToTrash(_ ids: [String], afterDismissing: Bool = false) async {
        guard let removed = await removeRows(ids, afterDismissing: afterDismissing) else { return }
        do {
            try await session.service.moveConversationsToTrash(ids: ids, for: patientID)
            trashed = removed
        } catch {
            putBack(removed)
            actionError = error.localizedDescription
        }
    }

    /// From the Trash folder: rows leave Trash for the inbox.
    private func restoreFromTrash(_ ids: [String], afterDismissing: Bool = false) async {
        guard let removed = await removeRows(ids, afterDismissing: afterDismissing) else { return }
        do {
            try await session.service.restoreConversationsFromTrash(ids: ids, for: patientID)
        } catch {
            putBack(removed)
            actionError = error.localizedDescription
        }
    }

    /// Undo from the bar: back into the folder they left.
    private func undoTrash() async {
        let restoring = trashed
        trashed = []
        do {
            try await session.service.restoreConversationsFromTrash(ids: restoring.map(\.id), for: patientID)
            if folder != .trash { putBack(restoring) }
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// Takes rows out of the list. From a thread's menu, lets the pop finish
    /// first, since the thread's binding points into the row.
    private func removeRows(_ ids: [String], afterDismissing: Bool) async -> [Conversation]? {
        if afterDismissing { try? await Task.sleep(for: .milliseconds(450)) }
        let removed = conversations.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return nil }
        withAnimation { conversations.removeAll { ids.contains($0.id) } }
        return removed
    }

    private func putBack(_ rows: [Conversation]) {
        withAnimation {
            conversations.append(contentsOf: rows)
            conversations.sort { $0.date > $1.date }
        }
    }

    private func load() async {
        isLoading = true
        trashed = []
        async let threads = try? session.service.conversations(in: folder, for: patientID)
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
    /// Handled by the list, which owns the conversations.
    var onBookmark: (_ id: String, _ isOn: Bool) -> Void = { _, _ in }
    var onMarkUnread: (_ id: String) -> Void = { _ in }
    var isInTrash = false
    var onTrash: (_ id: String) -> Void = { _ in }
    var onRestore: (_ id: String) -> Void = { _ in }
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var reply = ""
    @State private var includeOthers = true
    @State private var showsParticipants = false
    @State private var showsDiscardConfirmation = false
    @State private var isSending = false
    @State private var sendError: String?
    /// Uploaded and waiting to go with the reply.
    @State private var attachments: [MessageAttachment] = []
    @State private var uploadingCount = 0
    @State private var uploadError: String?
    @State private var showsPhotoPicker = false
    @State private var showsFileImporter = false
    @State private var photoItems: [PhotosPickerItem] = []
    @FocusState private var composerFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
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
        .safeAreaInset(edge: .bottom) {
            if conversation.canReply { composer } else { repliesClosedBar }
        }
        .navigationTitle(conversation.subject)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(conversation.isBookmarked ? "Remove Bookmark" : "Bookmark",
                           systemImage: conversation.isBookmarked ? "bookmark.slash" : "bookmark") {
                        onBookmark(conversation.id, !conversation.isBookmarked)
                    }
                    // Like Mail: marking unread leaves the thread.
                    Button("Mark as Unread", systemImage: "envelope.badge") {
                        let id = conversation.id
                        dismiss()
                        onMarkUnread(id)
                    }
                    Button("Participants", systemImage: "person.2") {
                        showsParticipants = true
                    }
                    Divider()
                    if isInTrash {
                        Button("Unarchive", systemImage: "tray.and.arrow.up") {
                            let id = conversation.id
                            dismiss()
                            onRestore(id)
                        }
                    } else {
                        Button("Archive", systemImage: "archivebox") {
                            let id = conversation.id
                            dismiss()
                            onTrash(id)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showsParticipants) {
            ParticipantsSheet(participants: conversation.participants)
        }
        .alert("Your reply wasn't sent", isPresented: .constant(sendError != nil)) {
            Button("OK") { sendError = nil }
        } message: {
            Text(sendError ?? "")
        }
        .alert("Couldn't attach the file", isPresented: .constant(uploadError != nil)) {
            Button("OK") { uploadError = nil }
        } message: {
            Text(uploadError ?? "")
        }
        .photosPicker(isPresented: $showsPhotoPicker, selection: $photoItems, maxSelectionCount: 5, matching: .images)
        .onChange(of: photoItems) {
            let items = photoItems
            guard !items.isEmpty else { return }
            photoItems = []
            for item in items { Task { await attachPhoto(item) } }
        }
        .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.pdf, .image, .plainText],
                      allowsMultipleSelection: true) { result in
            guard case let .success(urls) = result else { return }
            for url in urls { Task { await attachFile(url) } }
        }
        .task {
            conversation.isUnread = false
            // The full thread, plus when staff last viewed it.
            if let full = try? await session.service.conversation(id: conversation.id, for: session.patientID) {
                // The screen's bookmark state wins: it may have changed while
                // the thread loaded, and demo data never changes.
                let bookmarked = conversation.isBookmarked
                conversation = full
                conversation.isBookmarked = bookmarked
                conversation.isUnread = false
            }
        }
    }

    /// When staff have closed the thread to replies (`replyFlags.canReply`).
    private var repliesClosedBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Theme.brand)
                Text("This conversation can't be replied to.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if let url = session.portalURL(forConversation: conversation.id) {
                    Link("Open on Portal", destination: url)
                        .font(.footnote.weight(.semibold))
                        .tint(Theme.brand)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)
        }
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

                if !attachments.isEmpty || uploadingCount > 0 {
                    attachmentChips
                }

                HStack(alignment: .bottom, spacing: 10) {
                    Menu {
                        Button("Photo Library", systemImage: "photo.on.rectangle") { showsPhotoPicker = true }
                        Button("Choose File", systemImage: "folder") { showsFileImporter = true }
                    } label: {
                        Image(systemName: "paperclip")
                            .font(.title3)
                            .foregroundStyle(Theme.brand)
                            .frame(width: 38, height: 38)
                    }
                    .disabled(isSending)
                    .accessibilityLabel("Attach a file")

                    TextField("Write a reply…", text: $reply, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($composerFocused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color(.secondarySystemGroupedBackground), in: .capsule)
                        .overlay(Capsule().strokeBorder(Theme.hairline))

                    Button {
                        send()
                    } label: {
                        Group {
                            if isSending {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.headline.weight(.bold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(canSend ? Theme.brand : Theme.brandDisabled, in: .circle)
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
        !isSending && uploadingCount == 0 && !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var attachmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 6) {
                        Image(systemName: "doc")
                        Text(attachment.name)
                            .lineLimit(1)
                            .frame(maxWidth: 160)
                        Button {
                            attachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(attachment.name)")
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.brand.opacity(0.12), in: .capsule)
                }
                if uploadingCount > 0 {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Uploading…")
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemFill), in: .capsule)
                }
            }
        }
    }

    /// Photos go up as JPEG, which the portal can show whatever the
    /// library's original format (often HEIC).
    private func attachPhoto(_ item: PhotosPickerItem) async {
        uploadingCount += 1
        defer { uploadingCount -= 1 }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.85) else {
            uploadError = "That photo couldn't be read."
            return
        }
        let number = attachments.count + 1
        await upload(jpeg, fileName: "Photo \(number).jpg", mimeType: "image/jpeg")
    }

    private func attachFile(_ url: URL) async {
        uploadingCount += 1
        defer { uploadingCount -= 1 }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            uploadError = "\(url.lastPathComponent) couldn't be read."
            return
        }
        let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        await upload(data, fileName: url.lastPathComponent, mimeType: mimeType)
    }

    private func upload(_ data: Data, fileName: String, mimeType: String) async {
        do {
            let attachment = try await session.service.uploadAttachment(data, fileName: fileName, mimeType: mimeType,
                                                                         for: session.patientID)
            attachments.append(attachment)
        } catch {
            uploadError = error.localizedDescription
        }
    }

    /// The reply only appears in the thread once the portal has taken it;
    /// on failure the text stays in the box to try again.
    private func send() {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await session.service.sendReply(text, attachments: attachments, in: conversation,
                                                    includeOtherViewers: includeOthers, for: session.patientID)
                conversation.messages.append(
                    ConversationMessage(id: UUID().uuidString, authorName: "You", authorRole: nil,
                                        isFromMe: true, date: .now, body: text,
                                        attachmentNames: attachments.map(\.name)))
                reply = ""
                attachments = []
                composerFocused = false
            } catch {
                sendError = error.localizedDescription
            }
        }
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

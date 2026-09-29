import SwiftUI

/// What's new, Health app–style: cards grouped by when they happened, each
/// opening the message, result, letter or visit it's about. Upcoming
/// visits in the next week come first, under "Coming Up".
struct NotificationsView: View {
    let patientID: String
    @Environment(Session.self) private var session

    @State private var showsUnreadOnly = false
    /// Opened here, so their unread dots clear without waiting for a reload.
    @State private var opened: Set<String> = []
    /// Conversations marked unread or moved to Trash from here.
    @State private var markedUnread: Set<String> = []
    @State private var trashed: Set<String> = []
    /// The card tapped, whose page is pushed.
    @State private var openItem: NotificationItem?

    /// How far back read items are shown; unread ones show whatever their age.
    private static let window: TimeInterval = 30 * 24 * 3600

    var body: some View {
        AsyncSection {
            try await load()
        } content: { items in
            let shown = items.filter { !trashed.contains($0.id) && (!showsUnreadOnly || isUnread($0)) }
            ScrollView {
                if shown.isEmpty {
                    emptyState
                        .padding(.top, 60)
                } else {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        ForEach(NotificationGroup.grouped(shown), id: \.group) { section in
                            VStack(alignment: .leading, spacing: 10) {
                                SummarySectionHeader<Feature>(title: section.group.title)
                                ForEach(section.items) { card($0, in: section.group) }
                            }
                        }
                    }
                    .padding()
                }
            }
            .background(Color(.systemGroupedBackground))
        }
        // Opens the tapped card's message, result, letter or visit.
        .navigationDestination(item: $openItem) { destination($0.destination) }
        .navigationTitle("Notices")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Show", selection: $showsUnreadOnly) {
                        Label("All", systemImage: "tray.full").tag(false)
                        Label("Unread", systemImage: "circlebadge.fill").tag(true)
                    }
                } label: {
                    Image(systemName: showsUnreadOnly
                          ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel(showsUnreadOnly ? "Showing unread only" : "Filter")
            }
        }
    }

    private func isUnread(_ item: NotificationItem) -> Bool {
        markedUnread.contains(item.id) || (item.isUnread && !opened.contains(item.id))
    }

    @ViewBuilder
    private var emptyState: some View {
        if showsUnreadOnly {
            ContentUnavailableView("No Unread Notices", systemImage: "checkmark.circle",
                                   description: Text("You've seen everything new."))
        } else {
            ContentUnavailableView("You're All Caught Up", systemImage: "checkmark.circle",
                                   description: Text("New messages, results, letters and upcoming visits appear here."))
        }
    }

    // MARK: Cards

    private func card(_ item: NotificationItem, in group: NotificationGroup) -> some View {
        let unread = isUnread(item)
        // A button rather than a NavigationLink, so one tap both clears the
        // dot and opens the page; an extra tap gesture on a link inside a
        // scroll view can stop the link from firing.
        return Button {
            opened.insert(item.id)
            markedUnread.remove(item.id)
            openItem = item
        } label: {
            SummaryCard(category: item.category, systemImage: item.art.symbol, color: item.art.color,
                        detail: group.timeText(for: item.date)) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.headline.weight(unread ? .bold : .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        if !item.detail.isEmpty {
                            Text(item.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    if unread {
                        Circle()
                            .fill(Theme.brand)
                            .frame(width: 10, height: 10)
                            .padding(.top, 6)
                            .accessibilityHidden(true)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(unread ? "Unread" : "")
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func destination(_ destination: NotificationItem.Destination) -> some View {
        switch destination {
        case let .conversation(conversation):
            NotificationConversationView(
                conversation: conversation,
                onMarkedUnread: { markedUnread.insert("msg-\($0)") },
                onTrashed: { trashed.insert("msg-\($0)") })
        case let .result(result):
            TestResultDetailView(result: result)
        case let .letter(letter):
            PortalDocumentView(title: letter.title, id: letter.id,
                               shareName: "\(letter.title) – \(letter.date.mediumDate)") {
                try await session.service.letterHTML(letter, for: patientID)
            }
        case let .visit(appointment):
            AppointmentDetailView(appointment: appointment)
        }
    }

    // MARK: Loading

    /// Each source is optional, so one failing (e.g. letters) still shows the rest.
    private func load() async throws -> [NotificationItem] {
        let service = session.service
        async let conversations = try? service.conversations(for: patientID)
        async let results = try? service.testResults(for: patientID)
        async let letters = try? service.letters(for: patientID)
        async let appointments = try? service.appointments(for: patientID)

        let since = Date.now.addingTimeInterval(-Self.window)
        let weekAhead = Date.now.addingTimeInterval(7 * 24 * 3600)
        var items: [NotificationItem] = []

        for conversation in await conversations ?? [] where conversation.isUnread || conversation.date >= since {
            let last = conversation.lastMessage
            let preview = last.map { "\($0.isFromMe ? "You" : $0.authorName): \($0.body)" } ?? ""
            items.append(NotificationItem(
                id: "msg-\(conversation.id)", category: "Messages", art: Feature.messages.tileArt,
                title: conversation.subject,
                detail: preview.replacingOccurrences(of: "\n", with: " "),
                date: conversation.date, isUnread: conversation.isUnread,
                destination: .conversation(conversation)))
        }
        for result in await results ?? [] where result.isUnread || result.date >= since {
            let from = result.orderingProvider.isEmpty ? "" : " · Ordered by \(result.orderingProvider)"
            items.append(NotificationItem(
                id: "res-\(result.id)", category: "Test Results", art: Feature.testResults.tileArt,
                title: result.name, detail: (result.summary ?? "New result available") + from,
                date: result.date, isUnread: result.isUnread,
                destination: .result(result)))
        }
        for letter in await letters ?? [] where letter.isUnread || letter.date >= since {
            items.append(NotificationItem(
                id: "let-\(letter.id)", category: "Letters", art: Feature.letters.tileArt,
                title: letter.title, detail: letter.author.map { "From \($0)" } ?? "New letter",
                date: letter.date, isUnread: letter.isUnread,
                destination: .letter(letter)))
        }
        for visit in await appointments ?? []
        where visit.status == .scheduled && visit.date >= .now && visit.date <= weekAhead {
            let kind = visit.isTelehealth ? "Telehealth" : visit.department
            items.append(NotificationItem(
                id: "vis-\(visit.id)", category: "Visits", art: Feature.visits.tileArt,
                title: visit.title, detail: [kind, visit.provider].compactMap { $0 }.joined(separator: " · "),
                date: visit.date, isUnread: false,
                destination: .visit(visit)))
        }
        return items
    }
}

struct NotificationItem: Identifiable {
    enum Destination {
        case conversation(Conversation)
        case result(TestResult)
        case letter(Letter)
        case visit(Appointment)
    }

    let id: String
    let category: String
    let art: (symbol: String, color: Color)
    let title: String
    let detail: String
    let date: Date
    let isUnread: Bool
    let destination: Destination
}

/// By id, for `navigationDestination(item:)`.
extension NotificationItem: Hashable {
    static func == (lhs: NotificationItem, rhs: NotificationItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// The page's sections, in order. Upcoming visits sit above everything that
/// already happened.
private enum NotificationGroup: Int, CaseIterable {
    case comingUp, today, yesterday, thisWeek, earlier

    var title: String {
        switch self {
        case .comingUp: "Coming Up"
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thisWeek: "This Week"
        case .earlier: "Earlier"
        }
    }

    init(_ date: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let weekAgo = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        self = switch true {
        case date > .now: .comingUp
        case calendar.isDateInToday(date): .today
        case calendar.isDateInYesterday(date): .yesterday
        case date >= weekAgo: .thisWeek
        default: .earlier
        }
    }

    /// The card's time: just the time where the heading already says the
    /// day, the weekday this week, the date further back.
    func timeText(for date: Date) -> String {
        switch self {
        case .today, .yesterday:
            date.formatted(date: .omitted, time: .shortened)
        case .thisWeek:
            date.formatted(.dateTime.weekday(.wide))
        case .comingUp:
            Calendar.current.isDateInToday(date) || Calendar.current.isDateInTomorrow(date)
                ? "\(Calendar.current.isDateInToday(date) ? "Today" : "Tomorrow"), \(date.formatted(date: .omitted, time: .shortened))"
                : date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        case .earlier:
            date.mediumDate
        }
    }

    /// Soonest visit first; everything else newest first.
    static func grouped(_ items: [NotificationItem]) -> [(group: NotificationGroup, items: [NotificationItem])] {
        let byGroup = Dictionary(grouping: items) { NotificationGroup($0.date) }
        return allCases.compactMap { group in
            guard let items = byGroup[group] else { return nil }
            let sorted = group == .comingUp ? items.sorted { $0.date < $1.date } : items.sorted { $0.date > $1.date }
            return (group, sorted)
        }
    }
}

/// A conversation opened from a notification. The detail view edits its
/// conversation through a binding, so this holds the copy it works on, and
/// does the bookmark, unread and trash actions the Messages list would.
private struct NotificationConversationView: View {
    @State var conversation: Conversation
    var onMarkedUnread: (String) -> Void
    var onTrashed: (String) -> Void
    @Environment(Session.self) private var session

    var body: some View {
        ConversationDetailView(
            conversation: $conversation,
            onBookmark: { id, isOn in
                conversation.isBookmarked = isOn
                Task {
                    do {
                        try await session.service.setConversationsBookmarked(isOn, ids: [id], for: session.patientID)
                    } catch {
                        conversation.isBookmarked = !isOn
                    }
                }
            },
            // The detail view has already closed itself for these two.
            onMarkUnread: { id in
                Task {
                    try? await session.service.setConversationsUnread(true, ids: [id], for: session.patientID)
                    onMarkedUnread(id)
                }
            },
            onTrash: { id in
                Task {
                    if (try? await session.service.moveConversationsToTrash(ids: [id], for: session.patientID)) != nil {
                        onTrashed(id)
                    }
                }
            })
    }
}

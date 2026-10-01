import SwiftUI

/// Letters the hospital has shared (clinic letters, referrals, absence
/// letters), newest first and grouped by month. The filter in the top right
/// narrows the list to one kind of letter. Each opens in the document viewer,
/// laid out as the hospital wrote it.
struct LettersView: View {
    let patientID: String
    @Environment(Session.self) private var session
    /// A letter title to show only, or nil for all.
    @State private var titleFilter: String?
    @State private var searchText = ""

    var body: some View {
        AsyncSection {
            try await session.service.letters(for: patientID)
        } content: { letters in
            let shown = letters.filter { (titleFilter == nil || $0.title == titleFilter) && matches($0) }
            List {
                ForEach(byMonth(shown), id: \.month) { group in
                    Section(group.month.formatted(.dateTime.month(.wide).year())) {
                        ForEach(group.letters) { letter in
                            NavigationLink {
                                PortalDocumentView(title: letter.title, id: letter.id,
                                                   shareName: "\(letter.title) – \(letter.date.mediumDate)",
                                                   explains: .letter(letter)) {
                                    try await session.service.letterHTML(letter, for: patientID)
                                }
                            } label: {
                                LetterRow(letter: letter)
                            }
                        }
                    }
                }
            }
            .overlay {
                if letters.isEmpty {
                    ContentUnavailableView("No letters yet", systemImage: "envelope.open",
                                           description: Text("Letters the hospital shares with you will appear here."))
                } else if shown.isEmpty, !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else if shown.isEmpty, let titleFilter {
                    ContentUnavailableView {
                        Label("No \(titleFilter) letters", systemImage: "line.3.horizontal.decrease.circle")
                    } actions: {
                        Button("Show All Letters") { self.titleFilter = nil }
                    }
                }
            }
            .toolbar {
                if !letters.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) { filterMenu(letters) }
                }
            }
        }
        .navigationTitle(titleFilter ?? "Letters")
        .searchable(text: $searchText, prompt: "Search letters")
    }

    /// Title, author, or the date as shown (e.g. "12 Aug 2026", "August").
    private func matches(_ letter: Letter) -> Bool {
        guard !searchText.isEmpty else { return true }
        let fields = [letter.title, letter.author ?? "", letter.date.mediumDate,
                      letter.date.formatted(.dateTime.month(.wide).year())]
        return fields.contains { $0.localizedCaseInsensitiveContains(searchText) }
    }

    /// One option per letter title, with how many there are.
    private func filterMenu(_ letters: [Letter]) -> some View {
        let counts = Dictionary(grouping: letters, by: \.title).mapValues(\.count)
        let titles = counts.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return Menu {
            Picker("Show", selection: $titleFilter) {
                Text("All Letters (\(letters.count))").tag(String?.none)
                ForEach(titles, id: \.self) { title in
                    Text("\(title) (\(counts[title] ?? 0))").tag(Optional(title))
                }
            }
        } label: {
            Label("Filter", systemImage: titleFilter == nil
                  ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
    }

    private func byMonth(_ letters: [Letter]) -> [(month: Date, letters: [Letter])] {
        let calendar = Calendar.current
        return Dictionary(grouping: letters) {
            calendar.dateInterval(of: .month, for: $0.date)?.start ?? $0.date
        }
        .map { (month: $0.key, letters: $0.value.sorted { $0.date > $1.date }) }
        .sorted { $0.month > $1.month }
    }
}

struct LetterRow: View {
    let letter: Letter

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: letter.isUnread ? "envelope.badge.fill" : "envelope.open.fill")
                .font(.title3)
                .foregroundStyle(Feature.letters.accent)
                .frame(width: 40, height: 40)
                .background(Feature.letters.accent.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(letter.title)
                    .font(.headline)
                    .fontWeight(letter.isUnread ? .semibold : .regular)
                Text([letter.author, letter.date.mediumDate].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if letter.isUnread {
                Circle().fill(Theme.brand).frame(width: 10, height: 10)
                    .accessibilityLabel("Unread")
            }
        }
        .padding(.vertical, 4)
    }
}

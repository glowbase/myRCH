import SwiftUI

/// Letters the hospital has shared (clinic letters, referrals, absence
/// letters), newest first and grouped by year. Each opens in the document
/// viewer, laid out as the hospital wrote it.
struct LettersView: View {
    let patientID: String
    @Environment(Session.self) private var session

    var body: some View {
        AsyncSection {
            try await session.service.letters(for: patientID)
        } content: { letters in
            List {
                ForEach(byYear(letters), id: \.year) { group in
                    Section(String(group.year)) {
                        ForEach(group.letters) { letter in
                            NavigationLink {
                                PortalDocumentView(title: letter.title, id: letter.id,
                                                   shareName: "\(letter.title) – \(letter.date.mediumDate)") {
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
                }
            }
        }
        .navigationTitle("Letters")
    }

    private func byYear(_ letters: [Letter]) -> [(year: Int, letters: [Letter])] {
        let calendar = Calendar.current
        return Dictionary(grouping: letters) { calendar.component(.year, from: $0.date) }
            .map { (year: $0.key, letters: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.year > $1.year }
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

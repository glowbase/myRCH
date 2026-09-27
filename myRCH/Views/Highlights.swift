import SwiftUI

/// A plain-language observation for Home, like the Health app's Highlights:
/// worked out on the device from data the app has already loaded.
struct Highlight: Identifiable {
    let id: String
    var category: String
    var symbol: String
    var color: Color
    var text: String
    var feature: Feature?
}

extension Highlight {
    /// The most useful few, most time-sensitive first.
    static func make(upcoming: [Appointment], results: [TestResult], unreadMessages: Int,
                     medicationDoses: (due: Int, logged: Int), immunisations: [ImmunisationGroup],
                     now: Date = .now) -> [Highlight] {
        var items: [Highlight] = []
        let calendar = Calendar.current

        if let next = upcoming.first {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                               to: calendar.startOfDay(for: next.date)).day ?? 0
            let when = switch days {
            case ..<1: "today at \(next.date.formatted(date: .omitted, time: .shortened))"
            case 1: "tomorrow at \(next.date.formatted(date: .omitted, time: .shortened))"
            default: "in \(days) days, on \(next.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))"
            }
            items.append(Highlight(id: "next-visit", category: "Visits", symbol: Feature.visits.tileArt.symbol,
                                   color: Feature.visits.tileArt.color,
                                   text: "Your next visit, \(next.title), is \(when).", feature: .visits))
        }

        if medicationDoses.due > 0 {
            let remaining = medicationDoses.due - medicationDoses.logged
            let text = remaining <= 0
                ? "All of today's \(medicationDoses.due) scheduled doses are logged."
                : "\(remaining) of today's \(medicationDoses.due) scheduled doses \(remaining == 1 ? "is" : "are") still to log."
            items.append(Highlight(id: "doses", category: "Medication", symbol: Feature.medication.tileArt.symbol,
                                   color: Feature.medication.tileArt.color, text: text, feature: .medication))
        }

        let newResults = results.filter(\.isUnread)
        if !newResults.isEmpty {
            let text = newResults.count == 1
                ? "A new result is ready: \(newResults[0].name)."
                : "\(newResults.count) new results are ready to view."
            items.append(Highlight(id: "new-results", category: "Test Results", symbol: Feature.testResults.tileArt.symbol,
                                   color: Feature.testResults.tileArt.color, text: text, feature: .testResults))
        }

        let monthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        let flagged = results.filter { $0.isFlaggedAbnormal && $0.date > monthAgo }
        if !flagged.isEmpty {
            let text = flagged.count == 1
                ? "\(flagged[0].name) from the last month was flagged outside the normal range."
                : "\(flagged.count) results from the last month were flagged outside the normal range."
            items.append(Highlight(id: "flagged", category: "Test Results", symbol: "exclamationmark.triangle.fill",
                                   color: .orange, text: text, feature: .testResults))
        }

        if unreadMessages > 0 {
            items.append(Highlight(id: "messages", category: "Messages", symbol: Feature.messages.tileArt.symbol,
                                   color: Feature.messages.tileArt.color,
                                   text: unreadMessages == 1 ? "You have an unread message from the care team."
                                                             : "You have \(unreadMessages) unread messages from the care team.",
                                   feature: .messages))
        }

        if let latest = immunisations.compactMap({ group in group.dates.first.map { (group.name, $0) } })
            .max(by: { $0.1 < $1.1 }) {
            let ago = latest.1.formatted(.relative(presentation: .named, unitsStyle: .wide))
            items.append(Highlight(id: "immunisation", category: "Immunisations", symbol: "syringe.fill",
                                   color: Feature.immunisations.tileArt.color,
                                   text: "The most recent immunisation on file is \(latest.0), \(ago).",
                                   feature: .immunisations))
        }
        return items
    }
}

struct HighlightCard: View {
    let highlight: Highlight

    var body: some View {
        SummaryCard(category: highlight.category, systemImage: highlight.symbol, color: highlight.color) {
            Text(highlight.text)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

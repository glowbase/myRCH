import Foundation

/// Short descriptions of the child's record for prompts: recent results,
/// letters and medications. Each loads from the service's cache where it
/// can, and gives nothing rather than failing, so a feature still works
/// with whatever it could get.
enum RecordContext {
    /// Results collected in `interval`, newest first, flagged when the
    /// portal marks them outside the normal range. The list doesn't carry
    /// values, so no "within range" claim is made.
    static func results(_ session: Session, in interval: DateInterval, limit: Int = 10) async -> [String] {
        let all = (try? await session.service.testResults(for: session.patientID)) ?? []
        return all.filter { interval.contains($0.date) }
            .sorted(by: TestResult.newestFirst)
            .prefix(limit)
            .map { "- \($0.name), \($0.date.mediumDate)" + ($0.isAbnormal ? " (outside normal range)" : "") }
    }

    /// Letters dated in `interval`, newest first, by title and author.
    static func letters(_ session: Session, in interval: DateInterval, limit: Int = 5) async -> [String] {
        let all = (try? await session.service.letters(for: session.patientID)) ?? []
        return all.filter { interval.contains($0.date) }
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { letter in
                "- \(letter.title), \(letter.date.mediumDate)" + (letter.author.map { " from \($0)" } ?? "")
            }
    }

    /// Current medications by name.
    static func activeMedications(_ session: Session) async -> [String] {
        let all = (try? await session.service.medications(for: session.patientID)) ?? []
        return all.filter(\.isActive).map { "- \($0.reminderName)" }
    }

    /// The last `months` up to now.
    static func past(months: Int) -> DateInterval {
        let start = Calendar.current.date(byAdding: .month, value: -months, to: .now) ?? .now
        return DateInterval(start: start, end: .now)
    }

    /// A titled block for a prompt, or nothing when there are no lines.
    static func block(_ title: String, _ lines: [String]) -> [String] {
        lines.isEmpty ? [] : ["", "\(title):"] + lines
    }
}

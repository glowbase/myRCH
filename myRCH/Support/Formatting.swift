import Foundation

extension Date {
    /// e.g. "5 Feb 2025"
    var mediumDate: String {
        formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// e.g. "Feb 5, 2025 at 9:56 AM"
    var dateAndTime: String {
        formatted(date: .abbreviated, time: .shortened)
    }

    /// Relative label like "in 3 days" / "2 weeks ago".
    var relative: String {
        formatted(.relative(presentation: .named))
    }

    /// Time for today, weekday within the last week, otherwise "7 Sep".
    var shortRelativeDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return formatted(date: .omitted, time: .shortened)
        }
        if let week = calendar.date(byAdding: .day, value: -6, to: .now), self > week {
            return formatted(.dateTime.weekday(.abbreviated))
        }
        return formatted(.dateTime.day().month(.abbreviated))
    }

    /// Age from this date of birth, e.g. "12 months" under two, otherwise "8 years".
    var ageDescription: String {
        let parts = Calendar.current.dateComponents([.year, .month], from: self, to: .now)
        let years = parts.year ?? 0
        if years >= 2 { return "\(years) years" }
        let months = years * 12 + (parts.month ?? 0)
        return "\(months) month\(months == 1 ? "" : "s")"
    }
}

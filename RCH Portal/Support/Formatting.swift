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
}

import SwiftUI

// MARK: - Prompting

enum ResultExplainer {
    static let instructions = """
        You are explaining a child's test result. Normal ranges in children \
        vary with age, so a value just outside the range is often not a \
        concern. Only describe the results you are given; don't invent \
        values. Lab and care team comments matter: explain each one in plain \
        words. Labs often name germs they looked for but didn't find. "Not \
        isolated", "not detected", "not seen" and "no growth" mean the germ \
        was NOT found, which is usually reassuring, so say that clearly and \
        never describe it as an infection.
        """

    static let purposeRequest = "In two or three short sentences, explain what this test checks and why a doctor might order it. Reply with only the explanation."
    static let meaningRequest = "Now, in two to four short sentences, explain what these particular results likely mean, including what any comments say. Reply with only the explanation."
    /// Only asked when something is outside its range.
    static let causesRequest = "Now, for each result outside its normal range, in two to four short sentences in total, describe the common reasons a child's level can be low or high (as it is here), and what it can affect in a child's body if it stays that way. These are general possibilities, not what this child has. Reply with only the explanation."

    /// Whether any measured value (not a culture) is outside its range, so
    /// causes and effects are worth explaining.
    static func hasValuesOutOfRange(_ result: TestResult) -> Bool {
        result.components.contains { $0.organism == nil && $0.isAbnormal }
    }

    /// The model's context window is small, so long reports and comments are
    /// cut short.
    private static let reportLimit = 2_500
    private static let commentLimit = 600

    /// The cards for a result: what it's for and what it means, then causes
    /// and effects when something's out of range, then the child's
    /// conditions when any are recorded.
    static func brief(for result: TestResult, child: ChildContext) -> AIBrief {
        var sections = [
            AISection(title: "What this test is for", systemImage: "questionmark.circle.fill", request: purposeRequest),
            AISection(title: "What the result likely means", systemImage: "text.magnifyingglass", request: meaningRequest),
        ]
        if hasValuesOutOfRange(result) {
            sections.append(AISection(title: "Possible causes and effects", systemImage: "arrow.triangle.branch",
                                      request: causesRequest))
        }
        if let conditions = child.conditionsSection(about: "this result",
                                                    example: "such as why this test is often checked with that condition") {
            sections.append(conditions)
        }
        return AIBrief(context: prompt(for: result, age: child.age), sections: sections)
    }

    /// Describes the result for the model: what was tested and each value
    /// against its range. No names or identifiers are included; `age` is
    /// the child's age when the sample was collected.
    static func prompt(for result: TestResult, age: String?) -> String {
        var lines: [String] = []
        if let age { lines.append("Child's age when tested: \(age)") }
        lines.append("Test: \(result.name)")
        switch result.kind {
        case .lab: lines.append("Type: Lab test")
        case .imaging: lines.append("Type: Imaging")
        case .pathology: lines.append("Type: Pathology")
        }
        if let specimen = result.specimen, !specimen.isEmpty {
            lines.append("Specimen: \(specimen)")
        }
        lines.append("Status: \(result.status)")

        let organisms = result.components.compactMap(\.organism)
        // The lab's "Comment" lines are notes, not values, so they get their
        // own section rather than reading as a measurement.
        let isLabComment = { (component: ResultComponent) in
            component.name.localizedCaseInsensitiveCompare("Comment") == .orderedSame
        }
        let labComments = result.components.filter(isLabComment).compactMap(\.valueText)
        let measured = result.components.filter { $0.organism == nil && !isLabComment($0) }
        if !measured.isEmpty {
            lines.append("")
            lines.append("Results:")
            lines += measured.map { describe($0) }
        }
        if !organisms.isEmpty {
            lines.append("")
            lines.append("Culture grew:")
            lines += organisms.map { organism in
                "- \(organism.name)" + (organism.growthText.map { " (colony count: \($0))" } ?? "")
            }
        }
        if !labComments.isEmpty {
            lines.append("")
            lines.append("Lab comments:")
            lines += labComments.map { "- \(String($0.prefix(commentLimit)))" }
        }
        if !result.comments.isEmpty {
            lines.append("")
            lines.append("Comments from the care team:")
            lines += result.comments.map { "- \(String($0.text.prefix(commentLimit)))" }
        }
        if let summary = result.summary, !summary.isEmpty {
            lines.append("")
            lines.append("Report:")
            lines.append(String(summary.prefix(reportLimit)))
        }
        if result.components.isEmpty, result.summary == nil {
            lines.append("")
            lines.append("No values are available in the app, only the test name. The results are in the attached report or on the portal.")
        }
        return lines.joined(separator: "\n")
    }

    /// One value against its range, e.g. "- Zinc: 9 umol/L (normal range
    /// 10–18) – LOW, below normal range".
    static func describe(_ component: ResultComponent) -> String {
        let value = component.valueText
            ?? component.value?.formatted(.number.precision(.fractionLength(0...2)))
            ?? "not reported"
        var line = "- \(component.name): \(value)"
        if !component.unit.isEmpty { line += " \(component.unit)" }
        switch (component.normalLow, component.normalHigh) {
        case let (low?, high?): line += " (normal range \(low.formatted())–\(high.formatted()))"
        case let (nil, high?): line += " (normal: below \(high.formatted()))"
        case let (low?, nil): line += " (normal: above \(low.formatted()))"
        default: if let range = component.rangeText { line += " (normal: \(range))" }
        }
        if component.isAbnormal {
            // Which side matters for causes and effects. A censored value
            // ("<3") is only flagged when it's past the bound, so `value` is
            // enough to tell the side.
            if let value = component.value, let low = component.normalLow, value <= low {
                line += " – LOW, below normal range"
            } else if let value = component.value, let high = component.normalHigh, value >= high {
                line += " – HIGH, above normal range"
            } else {
                line += " – flagged by the lab as outside normal range"
            }
        } else if component.normalLow != nil || component.normalHigh != nil {
            line += " – within normal range"
        }
        return line
    }
}

// MARK: - Sheet

/// Explains a test result on device.
struct ResultExplanationSheet: View {
    let result: TestResult
    @Environment(Session.self) private var session

    var body: some View {
        AIExplainSheet(heading: result.name, navigationTitle: "Explain Result",
                       instructions: ResultExplainer.instructions) {
            let child = await ChildContext.load(session, at: result.date)
            return ResultExplainer.brief(for: result, child: child)
        }
    }
}

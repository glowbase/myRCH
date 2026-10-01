import FoundationModels
import OSLog
import SwiftUI

// MARK: - Prompting

enum ResultExplainer {
    static let logger = Logger(subsystem: "com.glowbase.myRCH", category: "ResultExplainer")

    /// Results routinely mention infections, organisms and abnormal findings,
    /// which the default guardrails reject. The permissive mode allows them,
    /// but only for plain-text responses, so each section is asked for as text.
    static let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)

    static let purposeRequest = "In two or three short sentences, explain what this test checks and why a doctor might order it. Reply with only the explanation."
    static let meaningRequest = "Now, in two to four short sentences, explain what these particular results likely mean, including what any comments say. Reply with only the explanation."

    /// Whether to offer the button at all: hidden on devices that can never
    /// run Apple Intelligence, shown otherwise (the sheet explains if it's
    /// switched off or still downloading).
    static var isSupported: Bool {
        SystemLanguageModel.default.availability != .unavailable(.deviceNotEligible)
    }

    static let instructions = """
        You help parents of children treated at The Royal Children's Hospital \
        Melbourne understand their child's test results. Write in Australian \
        English, in warm, plain language a parent without medical training can \
        follow. Explain medical terms when you use them. Be factual and calm. \
        Never diagnose, never suggest treatment, and never say a result is \
        definitely fine or definitely serious. Normal ranges in children vary \
        with age, so a value just outside the range is often not a concern. \
        Only describe the results you are given; don't invent values. \
        Lab and care team comments matter: explain each one in plain words. \
        Labs often name germs they looked for but didn't find. "Not \
        isolated", "not detected", "not seen" and "no growth" mean the germ \
        was NOT found, which is usually reassuring, so say that clearly and \
        never describe it as an infection.
        """

    /// The model's context window is small, so long reports and comments are
    /// cut short.
    private static let reportLimit = 2_500
    private static let commentLimit = 600

    /// Describes the result for the model: what was tested and each value
    /// against its range. No names or identifiers are included.
    static func prompt(for result: TestResult) -> String {
        var lines: [String] = []
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

    private static func describe(_ component: ResultComponent) -> String {
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
            line += " – outside normal range"
        } else if component.normalLow != nil || component.normalHigh != nil {
            line += " – within normal range"
        }
        return line
    }
}

// MARK: - Sheet

/// Streams an on-device explanation of a result, with a reminder that the
/// care team, not the model, is the authority.
struct ResultExplanationSheet: View {
    let result: TestResult
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case generating
        case done
        case unavailable(String)
        case failed
    }

    @State private var phase: Phase = .generating
    @State private var purpose: String?
    @State private var meaning: String?
    /// Bumped by "Try again" to restart the task.
    @State private var attempt = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(result.name)
                        .font(.system(.title2, design: .rounded).bold())
                        .foregroundStyle(Theme.ink)
                    content
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Explain Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: attempt) { await generate() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .unavailable(let message):
            ContentUnavailableView("Apple Intelligence unavailable", systemImage: "apple.intelligence",
                                   description: Text(message))
        case .failed:
            ContentUnavailableView {
                Label("Couldn't explain this result", systemImage: "exclamationmark.bubble")
            } description: {
                Text("The on-device model couldn't write an explanation for this result. Your care team can talk you through it.")
            } actions: {
                Button("Try again") { attempt += 1 }
            }
        case .generating, .done:
            section("What this test is for", systemImage: "questionmark.circle.fill", text: purpose)
            section("What the result likely means", systemImage: "text.magnifyingglass", text: meaning)
            disclaimer
        }
    }

    /// Shows a placeholder until the model reaches this section, then its
    /// text as it streams in.
    private func section(_ title: String, systemImage: String, text: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Theme.brand)
            if let text, !text.isEmpty {
                Text(text)
                    .foregroundStyle(.primary)
                    .contentTransition(.opacity)
            } else {
                Text("Placeholder text that stands in for the explanation while it's written.")
                    .redacted(reason: .placeholder)
                    .opacity(isGenerating ? 1 : 0)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
        .animation(.default, value: text)
    }

    private var disclaimer: some View {
        Label("Written by Apple Intelligence on this iPhone. Nothing leaves your device. It can make mistakes and isn't medical advice, so always check with your child's care team.",
              systemImage: "apple.intelligence")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var isGenerating: Bool {
        if case .generating = phase { true } else { false }
    }

    private func generate() async {
        switch ResultExplainer.model.availability {
        case .available:
            break
        case .unavailable(.appleIntelligenceNotEnabled):
            phase = .unavailable("Turn on Apple Intelligence in Settings to get explanations of results.")
            return
        case .unavailable(.modelNotReady):
            phase = .unavailable("Apple Intelligence is still getting ready on this iPhone. Try again in a little while.")
            return
        case .unavailable:
            phase = .unavailable("This iPhone can't run Apple Intelligence.")
            return
        }

        phase = .generating
        purpose = nil
        meaning = nil
        // One session, two turns: the second request sees the result from
        // the first, so it doesn't need repeating.
        let session = LanguageModelSession(model: ResultExplainer.model,
                                           instructions: ResultExplainer.instructions)
        do {
            let opening = ResultExplainer.prompt(for: result) + "\n\n" + ResultExplainer.purposeRequest
            try await stream(session.streamResponse(to: opening)) { purpose = $0 }
            try await stream(session.streamResponse(to: ResultExplainer.meaningRequest)) { meaning = $0 }
            phase = .done
        } catch is CancellationError {
            // The sheet closed; nothing to show.
        } catch {
            ResultExplainer.logger.error("Explanation failed for \(result.name, privacy: .public): \(String(describing: error), privacy: .public)")
            phase = .failed
        }
    }

    private func stream(_ response: LanguageModelSession.ResponseStream<String>,
                        into update: (String) -> Void) async throws {
        for try await snapshot in response {
            update(snapshot.content.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

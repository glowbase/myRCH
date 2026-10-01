import FoundationModels
import SwiftUI

// MARK: - Model output

/// A plain-language explanation of a test result, generated on device.
/// Properties generate in declaration order, so the purpose streams first.
@Generable
nonisolated struct ResultExplanation {
    @Guide(description: "Two or three short sentences, in plain language for a parent, on what this test checks and why a doctor might order it.")
    var purpose: String

    @Guide(description: "Two to four short sentences, in plain language for a parent, on what these particular results likely mean. Calm and factual, without diagnosing.")
    var meaning: String
}

// MARK: - Prompting

enum ResultExplainer {
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
        Only describe the results you are given; don't invent values.
        """

    /// The model's context window is small, so long reports are cut short.
    private static let reportLimit = 2_500

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
        let measured = result.components.filter { $0.organism == nil }
        if !measured.isEmpty {
            lines.append("")
            lines.append("Results:")
            lines += measured.map(describe)
        }
        if !organisms.isEmpty {
            lines.append("")
            lines.append("Culture grew:")
            lines += organisms.map { organism in
                "- \(organism.name)" + (organism.growthText.map { " (colony count: \($0))" } ?? "")
            }
        }
        if let summary = result.summary, !summary.isEmpty {
            lines.append("")
            lines.append("Report:")
            lines.append(String(summary.prefix(reportLimit)))
        }
        if result.components.isEmpty, result.summary == nil {
            lines.append("")
            lines.append("No values are available, only the test name. Explain what the test is for, and say the results are in the attached report or on the portal.")
        }

        lines.append("")
        lines.append("Explain what this test is for and what these results likely mean.")
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
    @State private var explanation: ResultExplanation.PartiallyGenerated?
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
            section("What this test is for", systemImage: "questionmark.circle.fill", text: explanation?.purpose)
            section("What the result likely means", systemImage: "text.magnifyingglass", text: explanation?.meaning)
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
        switch SystemLanguageModel.default.availability {
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
        explanation = nil
        let session = LanguageModelSession(instructions: ResultExplainer.instructions)
        let stream = session.streamResponse(to: ResultExplainer.prompt(for: result),
                                            generating: ResultExplanation.self)
        do {
            for try await snapshot in stream {
                explanation = snapshot.content
            }
            phase = .done
        } catch is CancellationError {
            // The sheet closed; nothing to show.
        } catch {
            phase = .failed
        }
    }
}

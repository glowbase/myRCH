import SwiftUI

/// A sentence or two on Home about what's new: unread results, letters and
/// messages, and a visit coming up. Written on device, only when there's
/// something new, and rewritten only when that changes.
struct HomeDigestCard: View {
    let results: [TestResult]
    let upcoming: [Appointment]
    let unreadMessages: Int
    @Environment(Session.self) private var session

    @State private var text: String?
    @State private var unreadLetters: [Letter] = []
    @State private var failed = false

    /// Digests already written this launch, by what they describe, so
    /// returning to Home doesn't run the model again.
    @MainActor private static var written: [String: String] = [:]

    private var newResults: [TestResult] { results.filter(\.isUnread) }

    /// A visit in the next week is worth a mention.
    private var soonVisit: Appointment? {
        upcoming.first { $0.date < Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now }
    }

    private var hasNews: Bool {
        !newResults.isEmpty || !unreadLetters.isEmpty || unreadMessages > 0 || soonVisit != nil
    }

    /// Changes whenever the digest needs rewriting.
    private var fingerprint: String {
        [session.patientID,
         newResults.map(\.id).joined(separator: ","),
         unreadLetters.map(\.id).joined(separator: ","),
         String(unreadMessages),
         soonVisit?.id ?? ""].joined(separator: "|")
    }

    var body: some View {
        // A stack, not a Group, so the tasks run while it's still empty.
        VStack(spacing: 0) {
            // Quietly absent when the model isn't ready or couldn't write
            // one: the cards below already show what's new.
            if hasNews, !failed, OnDeviceAI.unavailableReason == nil {
                card.padding(.top, 16)
            }
        }
        .task(id: session.patientID) {
            let letters = (try? await session.service.letters(for: session.patientID)) ?? []
            unreadLetters = letters.filter(\.isUnread)
        }
        .task(id: fingerprint) { await write() }
    }

    private var card: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(Theme.brand)
            VStack(alignment: .leading, spacing: 4) {
                if let text {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .contentTransition(.opacity)
                } else {
                    Text("A short summary of what's new in the record today.")
                        .font(.subheadline)
                        .redacted(reason: .placeholder)
                }
                Text("What's new · Apple Intelligence on this iPhone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
        .animation(.default, value: text)
        .accessibilityElement(children: .combine)
    }

    private func write() async {
        failed = false
        guard OnDeviceAI.unavailableReason == nil, hasNews else {
            text = nil
            return
        }
        if let cached = Self.written[fingerprint] {
            text = cached
            return
        }
        text = nil
        // Lets the record settle (letters arrive after results) before
        // spending a model run on it.
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        do {
            let digest = try await OnDeviceAI.respond(instructions: Self.instructions, prompt: prompt)
            guard !Task.isCancelled else { return }
            Self.written[fingerprint] = digest
            text = digest
        } catch is CancellationError {
            // Home changed or closed; the next run writes it.
        } catch {
            OnDeviceAI.logFailure("Home digest", error)
            failed = true
        }
    }

    private static let instructions = """
        You are writing one or two short sentences at the top of a parent's \
        app, telling them what's new in their child's hospital record. Use \
        only the facts given. Be friendly and calm. For results, only say \
        whether the lab marked any as outside the normal range, and suggest \
        opening them to see more; don't interpret them.
        """

    private var prompt: String {
        var lines: [String] = []
        if let name = session.activeAccount?.name.split(separator: " ").first {
            lines.append("Child's first name: \(name)")
        }
        if !newResults.isEmpty {
            lines.append("New test results (\(newResults.count)):")
            lines += newResults.prefix(5).map {
                "- \($0.name)" + ($0.isAbnormal ? " (outside normal range)" : "")
            }
        }
        if !unreadLetters.isEmpty {
            lines.append("New letters: " + unreadLetters.prefix(3).map(\.title).joined(separator: "; "))
        }
        if unreadMessages > 0 {
            lines.append("Unread messages from the care team: \(unreadMessages)")
        }
        if let soonVisit {
            lines.append("Next visit: \(soonVisit.title), \(soonVisit.date.formatted(.relative(presentation: .named)))")
        }
        lines.append("")
        lines.append("Write the one or two sentences. Reply with only them.")
        return lines.joined(separator: "\n")
    }
}

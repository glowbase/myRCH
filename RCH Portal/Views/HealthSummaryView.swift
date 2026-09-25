import SwiftUI

struct HealthSummaryView: View {
    let patientID: String
    @Environment(Session.self) private var session

    var body: some View {
        AsyncSection {
            try await load()
        } content: { summary in
            List {
                Section("Health Issues") {
                    ForEach(summary.issues) { issue in
                        LabeledContent(issue.name) {
                            if let date = issue.notedDate {
                                Text(date.mediumDate).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Allergies") {
                    ForEach(summary.allergies) { allergy in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(allergy.substance).font(.headline)
                                Spacer()
                                Text(allergy.severity)
                                    .font(.caption.bold())
                                    .foregroundStyle(.orange)
                            }
                            Text("Reaction: \(allergy.reaction)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                Section("Immunisations") {
                    ForEach(summary.immunisations) { shot in
                        LabeledContent(shot.name) {
                            Text(shot.date.mediumDate).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Health Summary")
    }

    private struct Summary {
        var issues: [HealthIssue]
        var allergies: [Allergy]
        var immunisations: [Immunisation]
    }

    private func load() async throws -> Summary {
        async let issues = session.service.healthIssues(for: patientID)
        async let allergies = session.service.allergies(for: patientID)
        async let immunisations = session.service.immunisations(for: patientID)
        return try await Summary(issues: issues, allergies: allergies, immunisations: immunisations)
    }
}

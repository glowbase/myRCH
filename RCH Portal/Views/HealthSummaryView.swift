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

struct AllergiesView: View {
    let patientID: String
    @Environment(Session.self) private var session

    var body: some View {
        AsyncSection {
            try await session.service.allergies(for: patientID)
        } content: { allergies in
            List {
                ForEach(allergies) { allergy in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(allergy.substance).font(.headline)
                            Spacer()
                            Text(allergy.severity)
                                .font(.caption.bold())
                                .foregroundStyle(Theme.red)
                        }
                        Text("Reaction: \(allergy.reaction)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .overlay {
                if allergies.isEmpty {
                    ContentUnavailableView("No allergies on file", systemImage: "allergens")
                }
            }
        }
        .navigationTitle("Allergies")
    }
}

struct ImmunisationsView: View {
    let patientID: String
    @Environment(Session.self) private var session

    var body: some View {
        AsyncSection {
            try await session.service.immunisations(for: patientID)
        } content: { shots in
            List {
                ForEach(ImmunisationGroup.group(shots)) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.name).font(.headline)
                        Text(group.dates.map(\.mediumDate).formatted(.list(type: .and)))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .overlay {
                if shots.isEmpty {
                    ContentUnavailableView("No immunisations on file", systemImage: "syringe")
                }
            }
        }
        .navigationTitle("Immunisations")
    }
}

/// Immunisations of the same vaccine collapsed into one entry, newest dose first.
struct ImmunisationGroup: Identifiable {
    var id: String { name }
    let name: String
    let dates: [Date]

    static func group(_ shots: [Immunisation]) -> [ImmunisationGroup] {
        Dictionary(grouping: shots, by: \.name)
            .map { ImmunisationGroup(name: $0.key, dates: $0.value.map(\.date).sorted(by: >)) }
            .sorted { ($0.dates.first ?? .distantPast) > ($1.dates.first ?? .distantPast) }
    }
}

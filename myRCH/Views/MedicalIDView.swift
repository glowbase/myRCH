import SwiftUI

/// One page with what staff need at a glance, like the Health app's Medical
/// ID: name, age and date of birth, UR number, allergies, conditions and
/// current medication. Full brightness while open, for showing at triage.
struct MedicalIDView: View {
    let patientID: String
    @Environment(Session.self) private var session

    @State private var header: RecordHeader?
    /// Nil when unknown: not readable yet, or failed to load.
    @State private var allergies: [Allergy]?
    @State private var conditions: [HealthIssue] = []
    @State private var medications: [Medication] = []
    @State private var isLoading = true
    @State private var copied = false

    private var account: LinkedAccount? { session.activeAccount }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Medical ID", systemImage: "staroflife.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                    Text(header?.fullName ?? account?.name ?? "")
                        .font(.system(.largeTitle, design: .rounded).bold())
                    if let birth = account?.dateOfBirth {
                        Text("\(birth.formatted(date: .long, time: .omitted)) · \(birth.ageDescription)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)

                if let ur = header?.urNumber {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("UR Number")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(ur)
                                .font(.system(.title, design: .monospaced).bold())
                                .textSelection(.enabled)
                                .accessibilityLabel(spokenDigits(ur))
                        }
                        Spacer()
                        Button {
                            UIPasteboard.general.string = ur
                            copied = true
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel(copied ? "Copied" : "Copy UR number")
                        .sensoryFeedback(.success, trigger: copied) { _, now in now }
                    }
                }
            }

            Section("Allergies") {
                if isLoading {
                    Text("Loading…")
                        .foregroundStyle(.secondary)
                } else if let allergies, allergies.isEmpty {
                    Text("No known allergies")
                        .foregroundStyle(.secondary)
                } else if let allergies {
                    ForEach(allergies) { allergy in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(allergy.substance).font(.headline)
                            let detail = [allergy.reaction, allergy.severity].filter { !$0.isEmpty }
                            if !detail.isEmpty {
                                Text(detail.joined(separator: " · "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    // Unknown: say so, in orange, rather than "none".
                    Label(AllergyNotice.text(readsAllergies: session.service.readsAllergies),
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.orange)
                }
            }

            Section("Conditions") {
                if conditions.isEmpty {
                    Text(isLoading ? "Loading…" : "None recorded")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(conditions) { Text($0.name) }
                }
            }

            Section("Current Medication") {
                if medications.isEmpty {
                    Text(isLoading ? "Loading…" : "None recorded")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(medications) { medication in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(medication.name).font(.headline)
                            if !medication.dose.isEmpty {
                                Text(medication.dose)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
            } footer: {
                Text("From the hospital's record in My RCH Portal. Check with the care team if anything looks out of date.")
            }
        }
        .navigationTitle("Medical ID")
        .navigationBarTitleDisplayMode(.inline)
        .fullBrightness()
        .task(id: patientID) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        let service = session.service
        async let headerTask = try? service.recordHeader(for: patientID)
        async let allergiesTask = try? service.allergies(for: patientID)
        async let issuesTask = try? service.healthIssues(for: patientID)
        async let medicationsTask = try? service.medications(for: patientID)
        header = await headerTask
        // Still fetched when unreadable, so the response's shape is logged.
        let loadedAllergies = await allergiesTask
        allergies = service.readsAllergies ? loadedAllergies : nil
        conditions = await issuesTask ?? []
        medications = (await medicationsTask ?? []).filter(\.isActive)
        isLoading = false
    }
}

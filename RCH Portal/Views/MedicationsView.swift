import SwiftUI

struct MedicationsView: View {
    let patientID: String
    @Environment(Session.self) private var session

    var body: some View {
        AsyncSection {
            try await session.service.medications(for: patientID)
        } content: { meds in
            List {
                Section("Current") {
                    ForEach(meds.filter(\.isActive)) { MedicationRow(medication: $0) }
                }
                let inactive = meds.filter { !$0.isActive }
                if !inactive.isEmpty {
                    Section("Past") {
                        ForEach(inactive) { MedicationRow(medication: $0) }
                    }
                }
            }
        }
        .navigationTitle("Medication")
    }
}

struct MedicationRow: View {
    let medication: Medication

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "pills.fill")
                .font(.title3)
                .foregroundStyle(medication.isActive ? Theme.brand : .secondary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(medication.name) \(medication.dose)").font(.headline)
                Text(medication.instructions)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(medication.prescriber)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

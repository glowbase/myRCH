import SwiftUI

struct AppointmentsView: View {
    let patientID: String
    @Environment(Session.self) private var session

    var body: some View {
        AsyncSection {
            try await session.service.appointments(for: patientID)
        } content: { appointments in
            let upcoming = appointments.filter { $0.status == .scheduled }
            let past = appointments.filter { $0.status != .scheduled }

            List {
                Section("Upcoming") {
                    if upcoming.isEmpty {
                        Text("You have no upcoming appointments")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(upcoming) { AppointmentRow(appointment: $0) }
                    }
                }
                Section("Past") {
                    ForEach(past) { AppointmentRow(appointment: $0) }
                }
            }
        }
        .navigationTitle("Appointments")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Book", systemImage: "plus") {}
            }
        }
    }
}

struct AppointmentRow: View {
    let appointment: Appointment

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 2) {
                Text(appointment.date.formatted(.dateTime.day()))
                    .font(.title3.bold())
                Text(appointment.date.formatted(.dateTime.month(.abbreviated)))
                    .font(.caption)
                    .textCase(.uppercase)
                Text(appointment.date.formatted(.dateTime.year()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44)
            .foregroundStyle(Theme.brand)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if appointment.isTelehealth {
                        Image(systemName: "phone.fill").font(.caption2)
                    }
                    Text(appointment.title).font(.headline)
                    if appointment.status == .missed {
                        Text("Missed")
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                    }
                }
                if let provider = appointment.provider {
                    Text(provider).font(.subheadline)
                }
                Text(appointment.department)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if appointment.hasVisitSummary {
                    Label("View After Visit Summary", systemImage: "doc.text")
                        .font(.footnote)
                        .foregroundStyle(Theme.brand)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

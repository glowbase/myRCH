import SwiftUI
import MapKit
import EventKit
import EventKitUI

// MARK: - List

struct AppointmentsView: View {
    let patientID: String
    @Environment(Session.self) private var session

    var body: some View {
        AsyncSection {
            try await session.service.appointments(for: patientID)
        } content: { appointments in
            let upcoming = appointments.filter { $0.status == .scheduled }.sorted { $0.date < $1.date }
            let past = appointments.filter { $0.status != .scheduled }.sorted { $0.date > $1.date }

            List {
                Section("Upcoming") {
                    if upcoming.isEmpty {
                        Text("You have no upcoming appointments")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(upcoming) { appointmentLink($0) }
                    }
                }
                Section("Past") {
                    ForEach(past) { appointmentLink($0) }
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

    private func appointmentLink(_ appointment: Appointment) -> some View {
        NavigationLink {
            AppointmentDetailView(appointment: appointment)
        } label: {
            AppointmentRow(appointment: appointment)
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
                            .foregroundStyle(Theme.orange)
                    }
                }
                if let provider = appointment.provider {
                    Text(provider).font(.subheadline)
                }
                Text(appointment.department)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if appointment.hasVisitSummary {
                    Label("After Visit Summary", systemImage: "doc.text")
                        .font(.footnote)
                        .foregroundStyle(Theme.brand)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail

struct AppointmentDetailView: View {
    let appointment: Appointment
    @Environment(\.openURL) private var openURL

    @State private var isCancelled = false
    @State private var wantsEarlierOffers = false
    @State private var completedSteps: Set<Int> = []
    @State private var showsChangeOptions = false
    @State private var showsCancelConfirmation = false
    @State private var showsAddToCalendar = false
    @State private var confirmation: String?

    private var isUpcoming: Bool { appointment.status == .scheduled && !isCancelled }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                timeCard
                if isUpcoming {
                    if appointment.isTelehealth { telehealthCard }
                    earlierOffersCard
                    if !appointment.instructions.isEmpty { preparationCard }
                }
                if appointment.status == .missed { missedCard }
                if let summary = appointment.visitSummary { summaryCard(summary) }
                careTeamCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Appointment")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Change this appointment?", isPresented: $showsChangeOptions, titleVisibility: .visible) {
            Button("Request a new time") {
                confirmation = "The clinic will contact you to arrange a new time."
            }
            Button("Cancel appointment", role: .destructive) {
                showsCancelConfirmation = true
            }
        }
        .alert("Cancel this appointment?", isPresented: $showsCancelConfirmation) {
            Button("Cancel appointment", role: .destructive) {
                isCancelled = true
                confirmation = "Your appointment has been cancelled. The clinic has been notified."
            }
            Button("Keep appointment", role: .cancel) {}
        } message: {
            Text("\(appointment.title) on \(appointment.date.mediumDate) will be cancelled.")
        }
        .alert("Request sent", isPresented: Binding(
            get: { confirmation != nil },
            set: { if !$0 { confirmation = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(confirmation ?? "")
        }
        .sheet(isPresented: $showsAddToCalendar) {
            AddToCalendarSheet(appointment: appointment)
                .ignoresSafeArea()
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusChip
            Text(appointment.title)
                .font(.system(.largeTitle, design: .rounded).bold())
                .foregroundStyle(Theme.ink)
            Text(appointment.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                .font(.headline)
                .foregroundStyle(.secondary)
            if isUpcoming {
                Text(appointment.date.formatted(.relative(presentation: .named)).capitalized)
                    .font(.subheadline)
                    .foregroundStyle(Theme.brand)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusChip: some View {
        let (text, icon, tint): (String, String, Color) = {
            if isCancelled { return ("Cancelled", "xmark.circle.fill", Theme.red) }
            switch appointment.status {
            case .scheduled:
                return appointment.isTelehealth
                    ? ("Phone appointment", "phone.fill", Theme.brand)
                    : ("In person", "building.2.fill", Theme.brand)
            case .completed: return ("Completed", "checkmark.circle.fill", Theme.green)
            case .missed: return ("Missed", "exclamationmark.circle.fill", Theme.orange)
            case .cancelled: return ("Cancelled", "xmark.circle.fill", Theme.red)
            }
        }()
        return Pill(text: text, systemImage: icon, tint: tint)
    }

    // MARK: Time + actions

    private var durationText: String {
        Duration.seconds(appointment.durationMinutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }

    private var timeCard: some View {
        card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(isUpcoming ? "Starts" : "Started") at \(appointment.date.formatted(date: .omitted, time: .shortened))")
                            .font(.title2.bold())
                        Text("\(durationText) · ends \(appointment.endDate.formatted(date: .omitted, time: .shortened))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if isUpcoming {
                    HStack(spacing: 10) {
                        actionButton("Add to Calendar", systemImage: "calendar.badge.plus") {
                            showsAddToCalendar = true
                        }
                        actionButton("Reschedule or Cancel", systemImage: "calendar.badge.clock") {
                            showsChangeOptions = true
                        }
                        if let url = directionsURL {
                            actionButton("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill") {
                                openURL(url)
                            }
                        } else if let url = phoneURL {
                            actionButton("Call Clinic", systemImage: "phone.fill") { openURL(url) }
                        }
                    }
                }
            }
        }
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Theme.brand)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(Theme.brand.opacity(0.1), in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: Upcoming extras

    private var telehealthCard: some View {
        card {
            iconRow(systemImage: "phone.badge.waveform.fill", tint: Theme.teal,
                    title: "Phone appointment",
                    detail: "Your clinician will call you at the appointment time. Keep your phone nearby and unmuted.")
        }
    }

    private var earlierOffersCard: some View {
        card {
            HStack(spacing: 14) {
                circleIcon("alarm.fill", tint: Theme.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Want to be seen earlier?")
                        .font(.subheadline.weight(.semibold))
                    Text("We'll let you know if an earlier time becomes available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Toggle("Notify me of earlier times", isOn: $wantsEarlierOffers)
                    .labelsHidden()
                    .tint(Theme.brand)
            }
        }
    }

    private var preparationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Before your visit")
            VStack(spacing: 0) {
                ForEach(Array(appointment.instructions.enumerated()), id: \.offset) { index, step in
                    let done = completedSteps.contains(index)
                    Button {
                        if done { completedSteps.remove(index) } else { completedSteps.insert(index) }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(done ? Theme.green : Color.secondary)
                                .contentTransition(.symbolEffect(.replace))
                            Text(step)
                                .font(.subheadline)
                                .foregroundStyle(done ? .secondary : .primary)
                                .strikethrough(done)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(done ? .isSelected : [])
                    if index < appointment.instructions.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        }
    }

    // MARK: Past extras

    private var missedCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                iconRow(systemImage: "exclamationmark.circle.fill", tint: Theme.orange,
                        title: "This appointment was missed",
                        detail: "Contact the clinic to arrange a new appointment.")
                if let url = phoneURL {
                    Button("Call to rebook", systemImage: "phone.fill") { openURL(url) }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .tint(Theme.brand)
                }
            }
        }
    }

    private func summaryCard(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("After Visit Summary")
            card {
                VStack(alignment: .leading, spacing: 12) {
                    Text(summary)
                        .font(.subheadline)
                    ShareLink(item: "\(appointment.title) – \(appointment.date.mediumDate)\n\n\(summary)") {
                        Label("Share summary", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(Theme.brand)
                }
            }
        }
    }

    // MARK: Care team + location

    private var careTeamCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(appointment.isTelehealth ? "Your care team" : "Care team & location")
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    AvatarView(initials: initials(of: appointment.provider ?? appointment.department),
                               tint: Theme.teal, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        if let provider = appointment.provider {
                            Text(provider).font(.headline)
                        }
                        Text(appointment.department)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(16)

                if appointment.address != nil {
                    locationMap
                }

                if let address = appointment.address {
                    detailRow(systemImage: "mappin.and.ellipse", title: "Address", value: address) {
                        if let url = directionsURL { openURL(url) }
                    }
                }
                if let checkIn = appointment.checkInLocation {
                    Divider().padding(.leading, 52)
                    detailRow(systemImage: "person.badge.clock.fill", title: "Check in at", value: checkIn)
                }
                if let phone = appointment.phone {
                    Divider().padding(.leading, 52)
                    detailRow(systemImage: "phone.fill", title: "Clinic phone", value: phone) {
                        if let url = phoneURL { openURL(url) }
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        }
    }

    /// Mock data only has RCH Parkville addresses, so the map is pinned there.
    private static let rchCoordinate = CLLocationCoordinate2D(latitude: -37.7939, longitude: 144.9497)

    private var locationMap: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: Self.rchCoordinate, latitudinalMeters: 700, longitudinalMeters: 700)),
            interactionModes: []) {
            Marker("The Royal Children's Hospital", systemImage: "cross.fill", coordinate: Self.rchCoordinate)
                .tint(Theme.red)
        }
        .frame(height: 150)
        .onTapGesture { if let url = directionsURL { openURL(url) } }
        .accessibilityLabel("Map of The Royal Children's Hospital. Double tap for directions.")
        .accessibilityAddTraits(.isButton)
    }

    private func detailRow(systemImage: String, title: String, value: String,
                           action: (() -> Void)? = nil) -> some View {
        let content = HStack(spacing: 14) {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.brand)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(.rect)

        return Group {
            if let action {
                Button(action: action) { content }.buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    // MARK: Building blocks

    private var directionsURL: URL? {
        guard !appointment.isTelehealth, let address = appointment.address,
              let query = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        return URL(string: "https://maps.apple.com/?daddr=\(query)")
    }

    private var phoneURL: URL? {
        guard let phone = appointment.phone else { return nil }
        return URL(string: "tel:\(phone.filter(\.isNumber))")
    }

    private func initials(of name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(Theme.ink)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    private func circleIcon(_ systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .foregroundStyle(tint)
            .frame(width: 40, height: 40)
            .background(tint.opacity(0.14), in: .circle)
    }

    private func iconRow(systemImage: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            circleIcon(systemImage, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Add to Calendar

/// System event editor, pre-filled with the appointment. On iOS 17+ it runs
/// out of process, so no calendar permission prompt is needed.
private struct AddToCalendarSheet: UIViewControllerRepresentable {
    let appointment: Appointment
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = context.coordinator.store
        let event = EKEvent(eventStore: store)
        event.title = "\(appointment.title) – \(appointment.department)"
        event.startDate = appointment.date
        event.endDate = appointment.endDate
        event.location = appointment.isTelehealth ? "Phone appointment" : appointment.address
        var notes: [String] = []
        if let provider = appointment.provider { notes.append("With \(provider)") }
        if let checkIn = appointment.checkInLocation { notes.append("Check in at \(checkIn)") }
        if let phone = appointment.phone { notes.append("Clinic: \(phone)") }
        event.notes = notes.joined(separator: "\n")
        event.addAlarm(EKAlarm(relativeOffset: -60 * 60))

        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let store = EKEventStore()
        let dismiss: DismissAction

        init(dismiss: DismissAction) { self.dismiss = dismiss }

        func eventEditViewController(_ controller: EKEventEditViewController,
                                     didCompleteWith action: EKEventEditViewAction) {
            dismiss()
        }
    }
}

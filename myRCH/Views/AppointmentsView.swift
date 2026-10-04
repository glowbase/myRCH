import SwiftUI
import MapKit
import EventKit
import EventKitUI
import WebKit
import PDFKit

// MARK: - Document styling

extension VisitDocument.Kind {
    /// Purple and royal blue: distinct from the app's teal, and dark enough
    /// to read as pill text (orange, yellow and green aren't).
    var tint: Color {
        switch self {
        case .careTeamNotes: Theme.proxy
        case .afterVisitSummary: Theme.blue
        }
    }

    var systemImage: String {
        switch self {
        case .careTeamNotes: "note.text"
        case .afterVisitSummary: "doc.text.fill"
        }
    }

    /// Short label for the list pills.
    var pillTitle: String {
        switch self {
        case .careTeamNotes: "Notes"
        case .afterVisitSummary: "After Visit Summary"
        }
    }
}

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
                // The next visit up top, as on Home.
                if let next = upcoming.first {
                    Section {
                        // Hidden link: a visible one would add a second chevron.
                        UpcomingAppointmentCard(appointment: next)
                            .background {
                                NavigationLink { AppointmentDetailView(appointment: next) } label: { EmptyView() }
                                    .opacity(0)
                            }
                            .summaryCardRow()
                    }
                }
                Section("Upcoming") {
                    if upcoming.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No upcoming visits")
                                .font(.subheadline.weight(.semibold))
                            Text("Appointments booked with the hospital appear here, with the time and where to go.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
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
    @Environment(Session.self) private var session
    /// Which documents the visit has, looked up as the row appears (the
    /// visits list doesn't say whether there are notes). Cached for 5 minutes.
    @State private var documentKinds: [VisitDocument.Kind]?

    /// Until the lookup returns, fall back to the list's own "has a summary"
    /// flag, so rows don't jump about.
    private var pillKinds: [VisitDocument.Kind] {
        documentKinds ?? (appointment.hasVisitSummary ? [.afterVisitSummary] : [])
    }

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
            .foregroundStyle(Feature.visits.accent)

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
                if !pillKinds.isEmpty {
                    ChipRow(spacing: 6, clipsToBounds: true) {
                        ForEach(pillKinds, id: \.self) { kind in
                            Pill(text: kind.pillTitle, systemImage: kind.systemImage, tint: kind.tint)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 4)
        .animation(.default, value: pillKinds)
        .task(id: appointment.id) {
            guard appointment.status != .scheduled else { return }
            if let documents = try? await session.service.visitDocuments(appointmentID: appointment.id,
                                                                         for: session.patientID) {
                // One pill per kind, notes first, however many notes there are.
                let kinds = Set(documents.map(\.kind))
                documentKinds = [VisitDocument.Kind.careTeamNotes, .afterVisitSummary].filter(kinds.contains)
            }
        }
    }
}

// MARK: - Visitor map

/// The hospital's visitor directory map (a public PDF on rch.org.au), for
/// finding the check-in desk.
private struct VisitorMapSheet: View {
    private static let url = URL(string: "https://www.rch.org.au/uploadedFiles/Main/Content/info/Visitor_Directory_Map.pdf")!

    @Environment(\.dismiss) private var dismiss
    @State private var pdf: PDFDocument?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if let pdf {
                    PDFKitView(document: pdf)
                        .ignoresSafeArea(edges: .bottom)
                } else if failed {
                    ContentUnavailableView {
                        Label("Couldn't load the map", systemImage: "map")
                    } description: {
                        Text("Check your internet connection and try again.")
                    } actions: {
                        Button("Try Again") { Task { await load() } }
                    }
                } else {
                    ProgressView("Loading map…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Visitor Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: Self.url)
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        failed = false
        // The shared URL cache keeps it for next time, subject to the server's headers.
        guard let (data, _) = try? await URLSession.shared.data(from: Self.url),
              let document = PDFDocument(data: data) else {
            failed = true
            return
        }
        pdf = document
    }
}

// MARK: - Rebook

/// Rebook: choose a reason and one of the portal's free times, a week at a
/// time, as on the portal's Reschedule page.
private struct RescheduleSheet: View {
    let appointment: Appointment
    let onRescheduled: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(Session.self) private var session

    @State private var options: RescheduleOptions?
    @State private var slots: [AppointmentSlot] = []
    @State private var reason: RescheduleOptions.Reason?
    @State private var selected: AppointmentSlot?
    @State private var loadError: String?
    @State private var isLoadingMore = false
    @State private var isBooking = false
    @State private var bookingError: String?

    private var canBook: Bool {
        guard session.service.booksReschedules, selected != nil, !isBooking else { return false }
        return reason != nil || !(options?.requiresReason ?? false)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let options {
                    form(options)
                } else if let loadError {
                    ContentUnavailableView {
                        Label("Couldn't find times", systemImage: "calendar.badge.exclamationmark")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Try Again") { Task { await load() } }
                    }
                } else {
                    ProgressView("Finding times…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Rebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isBooking {
                        ProgressView()
                    } else {
                        Button("Rebook") { Task { await book() } }
                            .disabled(!canBook)
                    }
                }
            }
        }
        .task { await load() }
        .alert("Couldn't rebook", isPresented: Binding(
            get: { bookingError != nil },
            set: { if !$0 { bookingError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(bookingError ?? "")
        }
    }

    /// The current booking and each free time as upcoming visit cards, like Home's.
    private func form(_ options: RescheduleOptions) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header("Current booking")
                UpcomingAppointmentCard(appointment: appointment, showsChevron: false)

                if !options.reasons.isEmpty {
                    reasonPicker(options)
                }

                header("Other times")
                    .padding(.top, 8)
                if slots.isEmpty, !isLoadingMore {
                    Text("There are no other times in the next \(options.lastDay - EpicDay.number(for: .now)) days.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(slots) { slotCard($0) }

                // Weeks arrive one search at a time; the cards fill in as they do.
                if isLoadingMore {
                    ProgressView(slots.isEmpty ? "Finding times…" : "Finding more times…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }

                if !session.service.booksReschedules {
                    Text("Booking a new time from the app isn't connected yet. To move this visit, call the clinic\(appointment.phone.map { " on \($0)" } ?? "") or use My RCH Portal.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(Theme.ink)
    }

    private func reasonPicker(_ options: RescheduleOptions) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Reason")
                Spacer()
                Picker("Reason", selection: $reason) {
                    Text("Choose").tag(RescheduleOptions.Reason?.none)
                    ForEach(options.reasons) { reason in
                        Text(reason.title).tag(Optional(reason))
                    }
                }
                .labelsHidden()
                .tint(Feature.visits.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
            if options.requiresReason {
                Text("The clinic needs a reason to move the visit.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
        }
    }

    /// The visit as it would be at this time, outlined when chosen.
    private func slotCard(_ slot: AppointmentSlot) -> some View {
        var moved = appointment
        moved.date = slot.date
        moved.durationMinutes = slot.lengthMinutes
        let isSelected = selected == slot
        return Button {
            selected = slot
        } label: {
            UpcomingAppointmentCard(appointment: moved, showsChevron: false)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .strokeBorder(Feature.visits.accent, lineWidth: isSelected ? 3 : 0)
                }
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white, Feature.visits.accent)
                            .padding(14)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func load() async {
        loadError = nil
        do {
            options = try await session.service.rescheduleOptions(appointmentID: appointment.id, for: session.patientID)
            await loadAllSlots()
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Each search covers about a week, so keep searching until the portal
    /// says there's nothing more (or the booking window ends).
    private func loadAllSlots() async {
        guard let options else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        var startDay: Int?
        var searched = Set<Int>()
        repeat {
            do {
                let page = try await session.service.rescheduleSlots(options, appointmentID: appointment.id,
                                                                      startDay: startDay, for: session.patientID)
                slots += page.slots.filter { new in !slots.contains { $0.id == new.id } }
                startDay = page.nextStartDay
            } catch {
                // Keep the times already found; only a first failure replaces the sheet.
                if slots.isEmpty { loadError = error.localizedDescription; self.options = nil }
                return
            }
            // Guard against a search that doesn't move forward.
            if let day = startDay, !searched.insert(day).inserted { break }
        } while startDay != nil && !Task.isCancelled
    }

    private func book() async {
        guard let options, let selected else { return }
        isBooking = true
        defer { isBooking = false }
        do {
            try await session.service.reschedule(appointmentID: appointment.id, to: selected, reason: reason,
                                                 options: options, for: session.patientID)
            onRescheduled(selected.date)
            dismiss()
        } catch {
            bookingError = error.localizedDescription
        }
    }
}

// MARK: - Detail

struct AppointmentDetailView: View {
    let appointment: Appointment
    @Environment(\.openURL) private var openURL
    @Environment(Session.self) private var session

    @State private var isCancelled = false
    @State private var wantsEarlierOffers: Bool
    @State private var isSavingEarlierOffers = false
    @State private var earlierOffersError: String?
    @State private var completedSteps: Set<Int> = []
    @State private var showsChangeOptions = false
    @State private var showsCancelConfirmation = false
    @State private var showsAddToCalendar = false
    @State private var confirmation: String?
    /// Notes and After Visit Summary, fetched when a past visit opens.
    @State private var documents: [VisitDocument] = []
    @State private var showsRecap = false
    @State private var showsVisitorMap = false

    init(appointment: Appointment) {
        self.appointment = appointment
        // Starts from the portal's setting; off when it couldn't be read.
        _wantsEarlierOffers = State(initialValue: appointment.isOnWaitList ?? false)
    }

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
                    AppointmentQuestionsCard(appointment: appointment)
                }
                if appointment.status == .missed { missedCard }
                documentsSections
                // The demo data's plain-text summary, where there's no portal AVS.
                if let summary = appointment.visitSummary,
                   !documents.contains(where: { $0.kind == .afterVisitSummary }) {
                    summaryCard(summary)
                }
                careTeamCard
            }
            .padding()
        }
        // For swipe-to-delete on the questions to ask.
        .swipeActionsContainerIfAvailable()
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Appointment")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsChangeOptions) {
            RescheduleSheet(appointment: appointment) { newDate in
                confirmation = "Your visit is now on \(newDate.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))."
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
        .toolbar {
            if appointment.status == .completed {
                AIExplainToolbarItem(title: "Visit Recap") { showsRecap = true }
            }
        }
        .sheet(isPresented: $showsRecap) { VisitRecapSheet(appointment: appointment, documents: documents) }
        .sheet(isPresented: $showsVisitorMap) { VisitorMapSheet() }
        .task(id: appointment.id) { await loadDocuments() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appointment.title)
                .font(.system(.largeTitle, design: .rounded).bold())
                .foregroundStyle(Theme.ink)
            ChipRow {
                statusChip
                if let desk = appointment.deskName {
                    CategoryChip(title: desk, systemImage: "mappin.circle.fill", color: Theme.red)
                }
            }
            Text(appointment.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                .font(.headline)
                .foregroundStyle(.secondary)
            if isUpcoming {
                Text(appointment.date.formatted(.relative(presentation: .named)).capitalized)
                    .font(.subheadline)
                    .foregroundStyle(Feature.visits.accent)
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
                    ? ("Phone appointment", "phone.fill", Feature.visits.accent)
                    : ("In person", "building.2.fill", Feature.visits.accent)
            case .completed: return ("Completed", "checkmark.circle.fill", Theme.green)
            case .missed: return ("Missed", "exclamationmark.circle.fill", Theme.orange)
            case .cancelled: return ("Cancelled", "xmark.circle.fill", Theme.red)
            }
        }()
        return CategoryChip(title: text, systemImage: icon, color: tint)
    }

    // MARK: Time + actions

    private var durationText: String {
        Duration.seconds(appointment.durationMinutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }

    private var timeCard: some View {
        card {
            VStack(alignment: .leading, spacing: 16) {
                timeline

                if isUpcoming {
                    HStack(alignment: .top, spacing: 10) {
                        actionButton("Add to Calendar", systemImage: "calendar.badge.plus", tint: Theme.blue) {
                            showsAddToCalendar = true
                        }
                        actionButton("Rebook", systemImage: "calendar.badge.clock", tint: Theme.orange) {
                            showsChangeOptions = true
                        }
                        actionButton("Cancel", systemImage: "xmark", tint: Theme.red) {
                            showsCancelConfirmation = true
                        }
                    }
                }
            }
        }
    }

    /// Start ── duration ── end, e.g. "Started 13:00 ── 30 min ── Ended 13:30".
    private var timeline: some View {
        let start = appointment.date.formatted(date: .omitted, time: .shortened)
        let end = appointment.endDate.formatted(date: .omitted, time: .shortened)
        let shortDuration = Duration.seconds(appointment.durationMinutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        return HStack(alignment: .center, spacing: 12) {
            timePoint(isUpcoming ? "Starts" : "Started", time: start, alignment: .leading)
            VStack(spacing: 6) {
                Label(shortDuration, systemImage: "hourglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Capsule()
                    .fill(Feature.visits.accent.opacity(0.35))
                    .frame(height: 3)
            }
            .frame(maxWidth: .infinity)
            timePoint(isUpcoming ? "Ends" : "Ended", time: end, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isUpcoming ? "Starts" : "Started") at \(start), \(durationText), \(isUpcoming ? "ends" : "ended") at \(end)")
    }

    private func timePoint(_ label: String, time: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Feature.visits.accent)
                .textCase(.uppercase)
            Text(time)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(Theme.ink)
        }
    }

    /// A tinted circle with its title underneath, like the Phone app's call buttons.
    private func actionButton(_ title: String, systemImage: String, tint: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 56, height: 56)
                    .background(tint.opacity(0.14), in: .circle)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
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
                if isSavingEarlierOffers {
                    ProgressView()
                }
                Toggle("Notify me of earlier times", isOn: Binding(
                    get: { wantsEarlierOffers },
                    set: { isOn in Task { await setEarlierOffers(isOn) } }))
                    .labelsHidden()
                    .tint(Feature.visits.accent)
                    .disabled(isSavingEarlierOffers)
            }
        }
        .alert("Couldn't update the wait list", isPresented: Binding(
            get: { earlierOffersError != nil },
            set: { if !$0 { earlierOffersError = nil } })) {
            Button("OK") { earlierOffersError = nil }
        } message: {
            Text(earlierOffersError ?? "")
        }
    }

    /// Flips the switch straight away, and back again if the portal refuses.
    private func setEarlierOffers(_ isOn: Bool) async {
        wantsEarlierOffers = isOn
        isSavingEarlierOffers = true
        defer { isSavingEarlierOffers = false }
        do {
            try await session.service.setEarlierVisitAlerts(isOn, appointmentID: appointment.id, for: session.patientID)
        } catch {
            wantsEarlierOffers = !isOn
            earlierOffersError = error.localizedDescription
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
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
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
                        .tint(Feature.visits.accent)
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
                    .tint(Feature.visits.accent)
                }
            }
        }
    }

    // MARK: Visit documents

    /// Loads a past visit's documents from the portal.
    private func loadDocuments() async {
        guard appointment.status != .scheduled else { return }
        documents = (try? await session.service.visitDocuments(appointmentID: appointment.id,
                                                               for: session.patientID)) ?? []
    }

    /// Care-team notes then the After Visit Summary, together under "Notes",
    /// each opening in the report viewer.
    @ViewBuilder
    private var documentsSections: some View {
        let ordered = documents.filter { $0.kind == .careTeamNotes }
            + documents.filter { $0.kind == .afterVisitSummary }
        if !ordered.isEmpty { documentsCard("Notes", ordered) }
    }

    private func documentsCard(_ title: String, _ items: [VisitDocument]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(title)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, document in
                    if index > 0 { Divider().padding(.leading, 62) }
                    NavigationLink {
                        VisitDocumentView(document: document, patientID: session.patientID)
                    } label: {
                        HStack(spacing: 14) {
                            circleIcon(document.kind.systemImage, tint: document.kind.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(document.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                let detail = [document.author, document.date?.mediumDate].compactMap { $0 }
                                if !detail.isEmpty {
                                    Text(detail.joined(separator: " · "))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
        }
    }

    // MARK: Care team + location

    private var careTeamCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(appointment.isTelehealth ? "Your Care Team" : "Care Team & Location")
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
                    detailRow(systemImage: "person.badge.clock.fill", title: "Check in at", value: checkIn) {
                        showsVisitorMap = true
                    }
                }
                if let phone = appointment.phone {
                    Divider().padding(.leading, 52)
                    detailRow(systemImage: "phone.fill", title: "Clinic phone", value: phone) {
                        if let url = phoneURL { openURL(url) }
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
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
                .foregroundStyle(Feature.visits.accent)
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
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
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

// MARK: - Visit document viewer

/// Shows a portal document (After Visit Summary, care-team notes) with the
/// portal's own layout and styling. JavaScript is off, and tapping a link
/// opens it in Safari rather than navigating away inside the viewer.
struct VisitDocumentView: View {
    let document: VisitDocument
    let patientID: String
    @Environment(Session.self) private var session

    var body: some View {
        PortalDocumentView(title: document.title, id: document.id, explains: .visitDocument(document)) {
            try await session.service.visitDocumentHTML(document, for: patientID)
        }
    }
}

/// Shows any portal document (visit notes, After Visit Summary, letters) as
/// the portal lays it out. JavaScript is off, and tapping a link opens it in
/// Safari rather than navigating away inside the viewer.
struct PortalDocumentView: View {
    let title: String
    /// Reloads when this changes.
    let id: String
    /// Names the shared PDF, e.g. "Referral Letter – 22 Sep 2026". Defaults to the title.
    var shareName: String? = nil
    /// Offers an on-device explanation of the document when set.
    var explains: ExplainableDocument? = nil
    let loadHTML: () async throws -> String
    @Environment(\.openURL) private var openURL

    @State private var page: WebPage?
    @State private var failure: String?
    /// The document as a paginated PDF, ready for the share sheet (which
    /// includes Print, AirDrop, Mail, Messages and Save to Files).
    @State private var pdfURL: URL?
    /// Kept for the explanation, which reads the document's text.
    @State private var html: String?
    @State private var showsExplanation = false

    var body: some View {
        Group {
            if let page {
                WebView(page)
                    .webViewTextSelection(.enabled)
                    .webViewLinkPreviews(.disabled)
                    .webViewBackForwardNavigationGestures(.disabled)
                    .ignoresSafeArea(edges: .bottom)
            } else if let failure {
                ContentUnavailableView {
                    Label("Couldn't open \(title)", systemImage: "doc.questionmark")
                } description: {
                    Text(failure)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let pdfURL {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: pdfURL,
                              preview: SharePreview(shareName ?? title, image: Image(systemName: "doc.richtext"))) {
                        Label("Share or Print", systemImage: "square.and.arrow.up")
                    }
                }
            }
            if let explains, html != nil {
                AIExplainToolbarItem(title: explains.buttonTitle) { showsExplanation = true }
            }
        }
        .sheet(isPresented: $showsExplanation) {
            if let explains, let html {
                DocumentExplanationSheet(document: explains, html: html)
            }
        }
        .task(id: id) { await load() }
        // The PDF is a copy of health data, so don't leave it behind.
        .onDisappear {
            if let pdfURL { try? FileManager.default.removeItem(at: pdfURL) }
        }
    }

    private func load() async {
        failure = nil
        do {
            let html = try await loadHTML()
            self.html = html
            pdfURL = DocumentPDF.write(html: html, named: shareName ?? title)
            var configuration = WebPage.Configuration()
            configuration.defaultNavigationPreferences.allowsContentJavaScript = false
            let page = WebPage(configuration: configuration,
                               navigationDecider: ReportLinkDecider(openURL: openURL))
            // The portal as base URL, so its host-relative stylesheets load.
            page.load(html: html, baseURL: URL(string: "https://\(MyChartConfig().host)")!)
            self.page = page
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// Lets the report itself load, but sends tapped links to Safari.
private struct ReportLinkDecider: WebPage.NavigationDeciding {
    let openURL: OpenURLAction

    mutating func decidePolicy(for action: WebPage.NavigationAction,
                               preferences: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
        if action.navigationType == .linkActivated, let url = action.request.url {
            openURL(url)
            return .cancel
        }
        return .allow
    }
}

// MARK: - PDF export

/// Turns a document's HTML into an A4, paginated PDF for sharing and
/// printing. UIKit's print renderer is used, not WebPage's export, because
/// that produces one very tall page that prints shrunk onto a single sheet.
enum DocumentPDF {
    /// Writes the PDF to a temporary file named after the document, with
    /// complete file protection. Returns nil if rendering fails.
    static func write(html: String, named name: String) -> URL? {
        let data = render(html: html)
        guard !data.isEmpty else { return nil }
        let folder = URL.temporaryDirectory.appending(path: "SharedDocuments", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeName = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let url = folder.appending(path: "\(safeName).pdf")
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch {
            return nil
        }
    }

    static func render(html: String) -> Data {
        let renderer = A4PageRenderer()
        renderer.addPrintFormatter(UIMarkupTextPrintFormatter(markupText: html), startingAtPageAt: 0)
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, renderer.paperRect, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for page in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    /// A4 (the Australian paper size) with 1.5 cm margins.
    private final class A4PageRenderer: UIPrintPageRenderer {
        private static let a4 = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        override var paperRect: CGRect { Self.a4 }
        override var printableRect: CGRect { Self.a4.insetBy(dx: 42.5, dy: 42.5) }
    }
}

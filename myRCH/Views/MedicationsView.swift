import SwiftUI

extension Medication {
    /// Name with strength, e.g. "Sodium Chloride 6% Solution" or
    /// "Levothyroxine 50 mcg". Portal names already include the strength and
    /// leave `dose` empty, so this avoids a dangling space.
    var displayName: String {
        dose.isEmpty ? name : "\(name) \(dose)"
    }

    /// The short name used in reminders: the brand name families know
    /// ("Hypersal"), else the prescription name.
    var reminderName: String { commonName ?? name }
}

extension Session {
    /// The viewed child's first name, so reminders stay clear with several
    /// children ("Time for Sam's Hypersal").
    var activeFirstName: String? {
        activeAccount?.name.split(separator: " ").first.map(String.init)
    }
}

extension Medication.Form {
    var systemImage: String {
        switch self {
        case .tablet: "pills.fill"
        case .capsule: "capsule.fill"
        case .liquid: "cross.vial.fill"
        case .inhaled: "lungs.fill"
        case .injection: "syringe.fill"
        case .topical: "bandage.fill"
        }
    }

    var label: String {
        switch self {
        case .tablet: "Tablet"
        case .capsule: "Capsule"
        case .liquid: "Liquid"
        case .inhaled: "Inhaled"
        case .injection: "Injection"
        case .topical: "Topical"
        }
    }
}

struct MedicationsView: View {
    let patientID: String
    @Environment(Session.self) private var session

    var body: some View {
        AsyncSection {
            try await session.service.medications(for: patientID)
        } content: { meds in
            List {
                MedicationLogSections(medications: meds)
                Section("Your Medications") {
                    if meds.contains(where: \.isActive) {
                        ForEach(meds.filter(\.isActive)) { link(to: $0) }
                    } else {
                        Text("Medication prescribed by the hospital appears here, with reminders you can set.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                let inactive = meds.filter { !$0.isActive }
                if !inactive.isEmpty {
                    Section("Past") {
                        ForEach(inactive) { link(to: $0) }
                    }
                }
            }
        }
        .navigationTitle("Medication")
    }

    private func link(to medication: Medication) -> some View {
        NavigationLink {
            MedicationDetailView(medication: medication)
        } label: {
            MedicationRow(medication: medication)
        }
    }
}

struct MedicationRow: View {
    let medication: Medication

    private var tint: Color { medication.isActive ? Feature.medication.accent : .secondary }

    var body: some View {
        HStack(spacing: 14) {
            // Same 40pt circle as the other dashboard rows, so icons line up
            // with each other and with the card's dividers.
            Image(systemName: medication.form.systemImage)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(medication.displayName).font(.headline)
                if !medication.instructions.isEmpty {
                    Text(medication.instructions)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !medication.prescriber.isEmpty {
                    Text(medication.prescriber)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        // Fill the row so every icon sits at the leading edge; without this
        // each row is centred by its own text width and the icons zigzag.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

// MARK: - Detail

struct MedicationDetailView: View {
    let medication: Medication
    @Environment(Session.self) private var session
    @Environment(MedicationStore.self) private var store

    @State private var newNote = ""
    @State private var notificationsDenied = false
    /// The day shown in the History section.
    @State private var historyDay = Calendar.current.startOfDay(for: .now)
    @FocusState private var isWritingNote: Bool

    private var storeKey: String {
        MedicationStore.key(patientID: session.patientID, medicationID: medication.id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if let commonName = medication.commonName { akaBanner(commonName) }
                if !medication.instructions.isEmpty {
                    section("How to Take It") {
                        Text(medication.instructions)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if medication.isActive {
                    if !reminders.isEmpty { historySection }
                    remindersSection
                }
                section("Prescription") { prescriptionDetails }
                if medication.isActive { repeatsSection }
                notesSection
                if medication.isPatientReported {
                    section("Good to Know") {
                        note("person.fill.checkmark",
                             "You added this medication. The care team will review it at the next visit.")
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Medication")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: AKA

    /// The brand or everyday name families and pharmacies often use instead,
    /// e.g. "Hypersal" for sodium chloride 6%.
    private func akaBanner(_ commonName: String) -> some View {
        HStack(spacing: 12) {
            Text("AKA")
                .font(.caption.weight(.heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Feature.medication.accent, in: .rect(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(commonName)
                    .font(.headline)
                Text("Also known as")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Feature.medication.accent.opacity(0.12), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Also known as \(commonName)")
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(medication.form.label, systemImage: medication.form.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Feature.medication.accent)
                .textCase(.uppercase)
            Text(medication.displayName)
                .font(.system(.title, design: .rounded).bold())
            HStack(spacing: 8) {
                Pill(text: medication.isActive ? "Current" : "Past",
                     systemImage: medication.isActive ? "checkmark.circle.fill" : "clock.arrow.circlepath",
                     tint: medication.isActive ? Theme.green : .secondary)
                if medication.isPatientReported {
                    Pill(text: "Added by you", systemImage: "person.fill.checkmark", tint: .secondary)
                }
            }
            .padding(.top, 2)
        }
    }

    // MARK: Prescription

    @ViewBuilder
    private var prescriptionDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let date = medication.prescribedDate {
                infoRow("Prescribed", date.mediumDate)
            }
            // Mock data puts the clinic in `prescriber` and the clinician in
            // `approvedBy`; the portal gives only the clinician, in `prescriber`.
            if let approvedBy = medication.approvedBy {
                infoRow("Prescribed by", approvedBy)
                if !medication.prescriber.isEmpty { infoRow("Clinic", medication.prescriber) }
            } else if !medication.prescriber.isEmpty {
                infoRow("Prescribed by", medication.prescriber)
            }
            if let quantity = medication.quantity {
                infoRow("Quantity", quantity)
            }
            if let days = medication.daySupply {
                infoRow("Supply", supplyText(days))
            }
        }
    }

    /// "14 days", or for long supplies "333 days (about 11 months)".
    private func supplyText(_ days: Int) -> String {
        let base = "\(days) day\(days == 1 ? "" : "s")"
        guard days >= 60 else { return base }
        let months = Int((Double(days) / 30.4).rounded())
        return "\(base) (about \(months) months)"
    }

    // MARK: Repeats

    private var repeatsSection: some View {
        section("Repeats") {
            if medication.canRequestRepeat {
                note("arrow.clockwise.circle.fill",
                     "Repeats can be requested for this medication. Ask your pharmacy or use the MyRCHPortal website.")
            } else {
                note("xmark.circle.fill",
                     "This prescription isn't available for repeat through Patient Portal.")
            }
        }
    }

    // MARK: Reminders

    private var reminders: [MedicationStore.Reminder] { store.reminders(for: storeKey) }

    private var remindersSection: some View {
        section("Reminders") {
            VStack(alignment: .leading, spacing: 12) {
                if reminders.isEmpty {
                    Text("Get a notification at each dose time, with a follow-up if it isn't logged.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(reminders) { reminder in
                    HStack {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(Feature.medication.accent)
                        DatePicker("Daily at", selection: timeBinding(for: reminder),
                                   displayedComponents: .hourAndMinute)
                        Button(role: .destructive) {
                            saveReminders(reminders.filter { $0.id != reminder.id })
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove reminder")
                    }
                }
                if notificationsDenied {
                    Text("Notifications are turned off for this app. Turn them on in Settings to get reminders.")
                        .font(.footnote)
                        .foregroundStyle(Theme.orange)
                }
                Button("Add Reminder", systemImage: "plus.circle.fill") { addReminder() }
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func timeBinding(for reminder: MedicationStore.Reminder) -> Binding<Date> {
        Binding {
            reminder.date
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            saveReminders(reminders.map {
                $0.id == reminder.id ? .init(id: $0.id, hour: parts.hour ?? 8, minute: parts.minute ?? 0) : $0
            })
        }
    }

    private func addReminder() {
        Task {
            guard await store.requestNotificationPermission() else {
                notificationsDenied = true
                return
            }
            notificationsDenied = false
            // Start at 8 am, or an hour after the latest existing reminder.
            let hour = reminders.last.map { min($0.hour + 1, 23) } ?? 8
            saveReminders(reminders + [.init(hour: hour, minute: 0)])
        }
    }

    private func saveReminders(_ updated: [MedicationStore.Reminder]) {
        store.setReminders(updated, for: storeKey, medicineName: medication.reminderName,
                           childName: session.activeFirstName)
    }

    // MARK: Today's doses

    /// This medication's dose history on the day strip, as in the Health
    /// app: rings fill as each day's doses are logged; pick a day to see
    /// when each dose was taken or skipped, and log any that were missed.
    private var historySection: some View {
        section("History") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(historyTitle).font(.headline)
                    // When it's meant to be taken; the strip shows when it was.
                    Label(scheduleText, systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                WeekStrip(selectedDay: $historyDay,
                          progress: { DayProgress(store.doses(on: $0, for: storeKey)) },
                          centreLabel: { centreLabel(on: $0) })
                // Let the strip run to the card's edges.
                .padding(.horizontal, -16)
                Divider()

                let doses = store.doses(on: historyDay, for: storeKey)
                let asNeeded = store.asNeededLogs(on: historyDay, for: storeKey)
                ForEach(doses) { dose in historyRow(dose) }
                ForEach(asNeeded, id: \.loggedAt) { log in
                    HStack(spacing: 10) {
                        Text(log.scheduled.formatted(date: .omitted, time: .shortened))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .frame(minWidth: 70, alignment: .leading)
                        Text("As needed")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Label("Taken", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.green)
                    }
                }
                if doses.isEmpty && asNeeded.isEmpty {
                    Text("Nothing scheduled or logged on this day.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("If a dose isn't logged, you'll get a follow-up reminder 30 minutes later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var historyTitle: String {
        let date = historyDay.formatted(.dateTime.day().month(.wide))
        if Calendar.current.isDateInToday(historyDay) { return "Today, \(date)" }
        return "\(historyDay.formatted(.dateTime.weekday(.wide))), \(date)"
    }

    private func historyRow(_ dose: MedicationStore.Dose) -> some View {
        HStack(spacing: 10) {
            Text(dose.scheduled.formatted(date: .omitted, time: .shortened))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .frame(minWidth: 70, alignment: .leading)
            Spacer()
            switch dose.status {
            case .taken?:
                loggedLabel(dose.loggedText("Taken"), "checkmark.circle.fill", Theme.green, dose)
            case .skipped?:
                loggedLabel(dose.loggedText("Skipped"), "xmark.circle.fill", .secondary, dose)
            case nil where dose.scheduled > .now:
                Text("Scheduled")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case nil:
                // Past and unlogged: can still be logged late.
                Button("Skip") { store.log(.skipped, scheduled: dose.scheduled, for: storeKey) }
                    .buttonStyle(.bordered)
                Button("Taken") { store.log(.taken, scheduled: dose.scheduled, for: storeKey) }
                    .buttonStyle(.borderedProminent)
                    .tint(Feature.medication.accent)
            }
        }
        .controlSize(.small)
    }

    /// "Scheduled daily at 8:00 am and 8:00 pm".
    private var scheduleText: String {
        let times = reminders.map { $0.date.formatted(date: .omitted, time: .shortened) }
        return "Scheduled daily at \(times.formatted(.list(type: .and)))"
    }

    /// Inside the centred day's ring: when the dose was logged as taken
    /// ("8:12"), or for several doses how many were taken ("2/3").
    private func centreLabel(on day: Date) -> String? {
        let doses = store.doses(on: day, for: storeKey)
        let taken = doses.filter { $0.status == .taken }
        guard !taken.isEmpty else { return nil }
        if doses.count == 1, let loggedAt = taken[0].loggedAt {
            return loggedAt.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
        }
        return "\(taken.count)/\(doses.count)"
    }

    /// A logged status; tap to undo if it was logged by mistake.
    private func loggedLabel(_ text: String, _ systemImage: String, _ tint: Color,
                             _ dose: MedicationStore.Dose) -> some View {
        Menu {
            Button("Undo", systemImage: "arrow.uturn.backward") {
                store.log(nil, scheduled: dose.scheduled, for: storeKey)
            }
        } label: {
            Label(text, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
        }
        .accessibilityHint("Double-tap to undo")
    }

    // MARK: Personal notes

    private var notesSection: some View {
        section("Personal Notes") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(store.notes(for: storeKey)) { saved in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(saved.text)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(saved.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contextMenu {
                        Button("Delete Note", systemImage: "trash", role: .destructive) {
                            store.deleteNote(saved, for: storeKey)
                        }
                    }
                    Divider()
                }
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Add a note, e.g. side effects or what works", text: $newNote, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($isWritingNote)
                    Button {
                        store.addNote(newNote, for: storeKey)
                        newNote = ""
                        isWritingNote = false
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(newNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Save note")
                }
                Label("Only saved on this phone. Not shared with the hospital.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Building blocks

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.bold())
            content()
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func note(_ systemImage: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(Feature.medication.accent)
            Text(text)
                .font(.subheadline)
        }
    }
}

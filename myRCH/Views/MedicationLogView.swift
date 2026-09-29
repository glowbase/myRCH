import SwiftUI

/// The top of the Medication screen, modelled on the Health app's: a day
/// title, a scrolling week strip whose rings fill as each day's doses are
/// logged, that day's scheduled doses, and a place to log as-needed doses.
/// Produces List sections, so it sits above "Your Medications".
struct MedicationLogSections: View {
    let medications: [Medication]
    @Environment(Session.self) private var session
    @Environment(MedicationStore.self) private var store

    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var showsAsNeeded = false

    private var calendar: Calendar { .current }
    private var current: [Medication] { medications.filter(\.isActive) }

    var body: some View {
        Section {
            WeekStrip(selectedDay: $selectedDay) { progress(on: $0) }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        } header: {
            Text(dayTitle)
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .textCase(nil)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
        }

        Section("Log") {
            let items = scheduled(on: selectedDay)
            if items.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No Medications Scheduled")
                    Text("Add reminder times on a medication to see its doses here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(items) { item in
                    ScheduledDoseRow(item: item, isFuture: selectedDay > calendar.startOfDay(for: .now))
                }
            }

            asNeededRow
            ForEach(asNeeded(on: selectedDay)) { entry in
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
                    Text(entry.medication.commonName ?? entry.medication.displayName)
                    Spacer()
                    Text(entry.log.scheduled.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        store.removeAsNeeded(entry.log, for: entry.key)
                    }
                }
                .accessibilityLabel("\(entry.medication.displayName), taken as needed at \(entry.log.scheduled.formatted(date: .omitted, time: .shortened))")
            }
        }
        .sheet(isPresented: $showsAsNeeded) {
            AsNeededSheet(medications: current) { medication in
                store.logAsNeeded(for: key(medication), at: asNeededTime)
            }
        }
        // Keep reminder names current, and fill them in for reminders set up
        // before names were saved.
        .task {
            for medication in current {
                store.updateNames(for: key(medication), medicineName: medication.reminderName,
                                  childName: session.activeFirstName)
            }
        }
    }

    // MARK: Pieces

    private var asNeededRow: some View {
        Button { showsAsNeeded = true } label: {
            HStack {
                Text("As-Needed Medications")
                Spacer()
                Image(systemName: "plus")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(Theme.brand)
        }
        .disabled(current.isEmpty || selectedDay > calendar.startOfDay(for: .now))
        .listRowBackground(Theme.brand.opacity(0.12))
    }

    /// "Today, 27 September", or "Friday, 25 September" for another day.
    private var dayTitle: String {
        let date = selectedDay.formatted(.dateTime.day().month(.wide))
        if calendar.isDateInToday(selectedDay) { return "Today, \(date)" }
        return "\(selectedDay.formatted(.dateTime.weekday(.wide))), \(date)"
    }

    /// Now if logging today; otherwise the same time of day on the chosen day.
    private var asNeededTime: Date {
        guard !calendar.isDateInToday(selectedDay) else { return .now }
        let time = calendar.dateComponents([.hour, .minute], from: .now)
        return calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: selectedDay) ?? selectedDay
    }

    // MARK: Data

    private func key(_ medication: Medication) -> String {
        MedicationStore.key(patientID: session.patientID, medicationID: medication.id)
    }

    struct Item: Identifiable {
        let medication: Medication
        let dose: MedicationStore.Dose
        let key: String
        var id: String { "\(key)|\(dose.scheduled.timeIntervalSince1970)" }
    }

    /// Every current medication's doses on `day`, in time order.
    private func scheduled(on day: Date) -> [Item] {
        current.flatMap { medication in
            store.doses(on: day, for: key(medication)).map { Item(medication: medication, dose: $0, key: key(medication)) }
        }
        .sorted { $0.dose.scheduled < $1.dose.scheduled }
    }

    struct AsNeededEntry: Identifiable {
        let medication: Medication
        let log: MedicationStore.DoseLog
        let key: String
        var id: Date { log.loggedAt }
    }

    private func asNeeded(on day: Date) -> [AsNeededEntry] {
        medications.flatMap { medication in
            store.asNeededLogs(on: day, for: key(medication)).map { AsNeededEntry(medication: medication, log: $0, key: key(medication)) }
        }
        .sorted { $0.log.scheduled < $1.log.scheduled }
    }

    /// How the day's scheduled doses went, across all current medications.
    private func progress(on day: Date) -> DayProgress? {
        DayProgress(scheduled(on: day).map(\.dose))
    }
}

// MARK: - Week strip

/// A scrolling row of days, each with a ring showing how much of that day's
/// schedule was logged. A tick fills the ring once every dose is logged.
struct WeekStrip: View {
    @Binding var selectedDay: Date
    let progress: (Date) -> DayProgress?
    /// Optional text inside the centred day's ring, e.g. when a dose was logged.
    var centreLabel: (Date) -> String? = { _ in nil }

    private let days: [Date] = {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        // Two weeks back, and the coming week, like the Health app.
        return (-14...6).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }()

    /// The day centred in the strip. Scrolling snaps a day into the centre,
    /// and whichever day settles there becomes the selected day.
    @State private var centredDay: Date?

    private static let itemWidth: CGFloat = 48
    private static let spacing: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            // Side margins let the first and last days reach the centre too.
            let sideMargin = max(0, (geometry.size.width - Self.itemWidth) / 2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Self.spacing) {
                    ForEach(days, id: \.self) { day in
                        DayRing(day: day, progress: progress(day),
                                isSelected: Calendar.current.isDate(day, inSameDayAs: selectedDay),
                                label: centreLabel(day))
                            .frame(width: Self.itemWidth)
                            .id(day)
                            // Tapping a day slides it into the centre.
                            .onTapGesture { withAnimation(.snappy) { centredDay = day } }
                    }
                }
                .scrollTargetLayout()
                .padding(.top, 14)
                .padding(.bottom, 8)
            }
            .contentMargins(.horizontal, sideMargin, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centredDay, anchor: .center)
            // A small fixed arrow pointing down at the centre day, as in Health.
            .overlay(alignment: .top) {
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 108)
        // A light tick each time a new day locks into the centre.
        .sensoryFeedback(.selection, trigger: selectedDay)
        .onAppear { centredDay = Calendar.current.startOfDay(for: selectedDay) }
        .onChange(of: centredDay) { _, day in
            if let day, !Calendar.current.isDate(day, inSameDayAs: selectedDay) {
                selectedDay = day
            }
        }
        // Keep the strip in step if the selection changes from elsewhere.
        .onChange(of: selectedDay) { _, day in
            let start = Calendar.current.startOfDay(for: day)
            if centredDay != start { withAnimation(.snappy) { centredDay = start } }
        }
    }
}

extension MedicationStore.Dose {
    /// "Taken 8:12 am": the status with the time it was logged, plus the
    /// date if it was logged on a different day. The scheduled time is
    /// shown separately, so both are always visible.
    func loggedText(_ status: String) -> String {
        guard let loggedAt else { return status }
        let time = loggedAt.formatted(date: .omitted, time: .shortened)
        let otherDay = Calendar.current.isDate(loggedAt, inSameDayAs: scheduled)
            ? "" : ", \(loggedAt.formatted(.dateTime.day().month(.abbreviated)))"
        return "\(status) \(time)\(otherDay)"
    }
}

/// How a day's scheduled doses went, as shares of the total (0...1).
struct DayProgress: Equatable {
    var taken: Double
    var skipped: Double

    var isComplete: Bool { taken + skipped >= 0.999 }

    /// From a day's doses; nil when nothing was scheduled.
    init?(_ doses: [MedicationStore.Dose]) {
        guard !doses.isEmpty else { return nil }
        let total = Double(doses.count)
        taken = Double(doses.filter { $0.status == .taken }.count) / total
        skipped = Double(doses.filter { $0.status == .skipped }.count) / total
    }
}

/// A day's doses as a filled circle: a pie of green for taken and grey for
/// skipped, over a pale circle for doses still to log. Solid green with a
/// tick when everything was taken, grey with a cross when everything was
/// skipped. `label` (e.g. "8:12" or "2/3") replaces the tick or cross.
struct DoseCircle: View {
    /// Nil when nothing is scheduled (or the day is still to come).
    let progress: DayProgress?
    var label: String? = nil
    var labelFont: Font = .system(size: 10, weight: .bold).monospacedDigit()
    var markFont: Font = .subheadline.weight(.bold)

    static let taken = Theme.green
    static let skipped = Color(.systemGray)

    /// Entirely one colour, so text on it should be white.
    private var isSolid: Bool {
        guard let progress, progress.isComplete else { return false }
        return progress.skipped == 0 || progress.taken == 0
    }

    var body: some View {
        ZStack {
            Circle().fill(Color(.tertiarySystemFill))
            if let progress {
                // Taken from the top, then skipped continuing clockwise.
                PieSlice(start: 0, end: progress.taken).fill(Self.taken)
                PieSlice(start: progress.taken, end: progress.taken + progress.skipped).fill(Self.skipped)
                if let label {
                    Text(label)
                        .font(labelFont)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .foregroundStyle(isSolid ? Color.white : .primary)
                        .padding(.horizontal, 4)
                } else if isSolid {
                    Image(systemName: progress.skipped == 0 ? "checkmark" : "xmark")
                        .font(markFont)
                        .foregroundStyle(.white)
                }
            }
        }
        .animation(.spring, value: progress)
    }
}

/// A wedge of a circle from `start` to `end`, as shares of a full turn
/// clockwise from the top.
struct PieSlice: Shape {
    var start: Double
    var end: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(start, end) }
        set { (start, end) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard end > start else { return path }
        let radius = min(rect.width, rect.height) / 2
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        // A whole circle, so there's no seam line from the centre.
        if end - start >= 0.999 {
            path.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
            return path
        }
        path.move(to: centre)
        path.addArc(center: centre, radius: radius,
                    startAngle: .degrees(start * 360 - 90), endAngle: .degrees(end * 360 - 90), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// One day: its weekday letter and a `DoseCircle`. The centred day can
/// also show a label inside (e.g. the time a dose was logged).
private struct DayRing: View {
    let day: Date
    let progress: DayProgress?
    let isSelected: Bool
    /// Shown inside the ring while this day is centred.
    var label: String? = nil

    private var isFuture: Bool { day > Calendar.current.startOfDay(for: .now) }

    var body: some View {
        VStack(spacing: 8) {
            // Weekday initial, circled when selected (as in Health).
            Text(day.formatted(.dateTime.weekday(.narrow)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color(.systemBackground) : .secondary)
                .frame(width: 28, height: 28)
                .background(isSelected ? Color.primary : .clear, in: .circle)
            DoseCircle(progress: isFuture ? nil : progress, label: isSelected ? label : nil)
                .frame(width: 40, height: 40)
        }
        .frame(width: 48)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue(progressDescription)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var progressDescription: String {
        guard let progress else { return "No doses scheduled" }
        if isFuture { return "Upcoming" }
        var parts: [String] = []
        if progress.taken > 0 { parts.append("\(Int((progress.taken * 100).rounded())) percent taken") }
        if progress.skipped > 0 { parts.append("\(Int((progress.skipped * 100).rounded())) percent skipped") }
        let summary = parts.isEmpty ? "Nothing logged" : parts.joined(separator: ", ")
        if isSelected, let label { return "\(summary). Logged \(label)" }
        return summary
    }
}

// MARK: - Rows and sheet

private struct ScheduledDoseRow: View {
    let item: MedicationLogSections.Item
    let isFuture: Bool
    @Environment(MedicationStore.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            Text(item.dose.scheduled.formatted(date: .omitted, time: .shortened))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(minWidth: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.medication.commonName ?? item.medication.displayName)
                    .font(.headline)
                if item.medication.commonName != nil {
                    Text(item.medication.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            status
                // A little bounce and tap when a dose is logged, like Health.
                .symbolEffect(.bounce, value: item.dose.status)
                .sensoryFeedback(trigger: item.dose.status) { _, new in
                    new == nil ? nil : .success
                }
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private var status: some View {
        switch item.dose.status {
        case .taken?:
            loggedMenu(item.dose.loggedText("Taken"), "checkmark.circle.fill", Theme.green)
        case .skipped?:
            loggedMenu(item.dose.loggedText("Skipped"), "xmark.circle.fill", .secondary)
        case nil where isFuture:
            Text("Scheduled")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case nil:
            HStack(spacing: 6) {
                Button("Skip") { store.log(.skipped, scheduled: item.dose.scheduled, for: item.key) }
                    .buttonStyle(.bordered)
                Button("Taken") { store.log(.taken, scheduled: item.dose.scheduled, for: item.key) }
                    .buttonStyle(.borderedProminent)
                    .tint(Feature.medication.accent)
            }
        }
    }

    private func loggedMenu(_ text: String, _ systemImage: String, _ tint: Color) -> some View {
        Menu {
            Button("Undo", systemImage: "arrow.uturn.backward") {
                store.log(nil, scheduled: item.dose.scheduled, for: item.key)
            }
        } label: {
            Label(text, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
        }
    }
}

/// Pick which medication was taken outside its schedule.
private struct AsNeededSheet: View {
    let medications: [Medication]
    let onLog: (Medication) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(medications) { medication in
                Button {
                    onLog(medication)
                    dismiss()
                } label: {
                    MedicationRow(medication: medication)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Log As-Needed Dose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Reminder logging sheet

/// Opened by tapping a medication reminder: everything due for that child at
/// that time, to log one by one or all at once. Works from the saved reminder
/// details alone, so it opens instantly, without waiting for the portal.
struct DoseLogSheet: View {
    let slot: MedicationStore.Slot
    @Environment(MedicationStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var items: [MedicationStore.SlotItem] { store.items(in: slot) }
    private var time: String { slot.scheduled.formatted(date: .omitted, time: .shortened) }

    private var subtitle: String {
        let day = Calendar.current.isDateInToday(slot.scheduled)
            ? "Today" : slot.scheduled.formatted(.dateTime.weekday(.wide).day().month(.wide))
        return [day, store.childName(in: slot)].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if items.isEmpty {
                        Text("Nothing is scheduled at this time any more.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(items) { item in
                        HStack {
                            Text(item.name).font(.headline)
                            Spacer()
                            switch item.status {
                            case .taken?:
                                logged("Taken", "checkmark.circle.fill", Theme.green, item)
                            case .skipped?:
                                logged("Skipped", "xmark.circle.fill", .secondary, item)
                            case nil:
                                HStack(spacing: 6) {
                                    Button("Skip") { store.log(.skipped, scheduled: slot.scheduled, for: item.key) }
                                        .buttonStyle(.bordered)
                                    Button("Taken") { store.log(.taken, scheduled: slot.scheduled, for: item.key) }
                                        .buttonStyle(.borderedProminent)
                                        .tint(Feature.medication.accent)
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                } header: {
                    Text(subtitle)
                }

                if items.contains(where: { $0.status == nil }) {
                    Section {
                        Button {
                            store.logAll(.taken, in: slot)
                        } label: {
                            Label("Log All as Taken", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.semibold)
                        }
                        .tint(Feature.medication.accent)
                    }
                }
            }
            .navigationTitle("\(time) Medications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// A logged status; tap to undo if it was logged by mistake.
    private func logged(_ text: String, _ systemImage: String, _ tint: Color,
                        _ item: MedicationStore.SlotItem) -> some View {
        Menu {
            Button("Undo", systemImage: "arrow.uturn.backward") {
                store.log(nil, scheduled: slot.scheduled, for: item.key)
            }
        } label: {
            Label(text, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
        }
    }
}

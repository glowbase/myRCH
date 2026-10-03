import SwiftUI

enum WatchColors {
    static let teal = Color(red: 0.13, green: 0.62, blue: 0.74)
    static let medication = Color(red: 0.35, green: 0.78, blue: 0.98)
}

/// Today's doses as a filled circle, like the phone app's `DoseCircle`: a
/// pie of logged doses over a pale circle, with the count on top.
private struct FilledProgressCircle: View {
    /// Share of today's doses logged, 0...1.
    let progress: Double
    let tint: Color
    let label: String

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.25))
            PieWedge(end: progress).fill(tint)
            Text(label)
                .font(.system(.footnote, design: .rounded).bold())
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                // Dark text on the green pie; white on the pale circle.
                .foregroundStyle(progress >= 0.5 ? Color.black : .white)
        }
    }
}

/// A wedge from the top, clockwise to `end` (a share of a full turn).
private struct PieWedge: Shape {
    let end: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard end > 0 else { return path }
        let radius = min(rect.width, rect.height) / 2
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        if end >= 0.999 {
            path.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
            return path
        }
        path.move(to: centre)
        path.addArc(center: centre, radius: radius,
                    startAngle: .degrees(-90), endAngle: .degrees(end * 360 - 90), clockwise: false)
        path.closeSubpath()
        return path
    }
}

struct ContentView: View {
    @Environment(WatchStore.self) private var store
    @AppStorage("watchChildID") private var childID = ""
    @State private var isChoosingChild = false

    private var child: WidgetSnapshot.Child? {
        store.snapshot?.child(childID.isEmpty ? nil : childID)
    }

    var body: some View {
        NavigationStack {
            if let child {
                DashboardView(
                    child: child,
                    received: store.received,
                    canChooseChild: (store.snapshot?.children.count ?? 0) > 1,
                    chooseChild: { isChoosingChild = true }
                )
            } else {
                ContentUnavailableView {
                    Label("Open myRCH on iPhone", systemImage: "iphone")
                } description: {
                    Text("Load your child's details on iPhone, then open this app again.")
                }
            }
        }
        .tint(WatchColors.teal)
        .sheet(isPresented: $isChoosingChild) {
            ChildPickerView(
                children: Array(store.snapshot?.children.values ?? [:].values)
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                childID: $childID
            )
        }
    }
}

private struct DashboardView: View {
    let child: WidgetSnapshot.Child
    let received: Date?
    let canChooseChild: Bool
    let chooseChild: () -> Void

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("myRCH")
                            .font(.caption)
                            .foregroundStyle(WatchColors.teal)
                        Text(child.name)
                            .font(.title3.weight(.semibold))
                    }
                    Spacer()
                    if canChooseChild {
                        Button(action: chooseChild) {
                            Image(systemName: "person.2.fill")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Choose child")
                    }
                }
            }

            Section {
                NavigationLink {
                    DosesView(child: child)
                } label: {
                    DashboardRow(
                        title: "Medication",
                        detail: medicationSummary,
                        systemImage: "pills.fill",
                        color: WatchColors.medication
                    )
                }

                NavigationLink {
                    VisitView(child: child)
                } label: {
                    DashboardRow(
                        title: "Next Visit",
                        detail: visitSummary,
                        systemImage: child.nextVisit?.isTelehealth == true ? "video.fill" : "calendar",
                        color: .red
                    )
                }

                NavigationLink {
                    UpdatesView(child: child)
                } label: {
                    DashboardRow(
                        title: "Updates",
                        detail: updatesSummary,
                        systemImage: "bell.badge.fill",
                        color: .orange
                    )
                }

                NavigationLink {
                    MedicalIDView(child: child)
                } label: {
                    DashboardRow(
                        title: "Medical ID",
                        detail: child.urNumber == nil ? "Open on iPhone to load" : "UR number and allergies",
                        systemImage: "staroflife.fill",
                        color: .red
                    )
                }
            }

            if let received {
                Text("Updated \(received, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Home")
    }

    private var medicationSummary: String {
        if child.dosesDue == 0 {
            return "No reminders today"
        }
        let remaining = max(child.dosesDue - child.dosesLogged, 0)
        return remaining == 0 ? "All logged" : "\(remaining) remaining"
    }

    private var visitSummary: String {
        guard let visit = child.nextVisit else { return "No upcoming visits" }
        return visit.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private var updatesSummary: String {
        let total = child.unreadMessages + child.newResults
        return total == 0 ? "Nothing new" : "\(total) new"
    }
}

private struct DashboardRow: View {
    let title: LocalizedStringKey
    let detail: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct ChildPickerView: View {
    let children: [WidgetSnapshot.Child]
    @Binding var childID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(children) { child in
                Button {
                    childID = child.id
                    dismiss()
                } label: {
                    HStack {
                        Text(child.name)
                        Spacer()
                        if child.id == childID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(WatchColors.teal)
                        }
                    }
                }
            }
            .navigationTitle("Choose Child")
        }
    }
}

private struct DosesView: View {
    let child: WidgetSnapshot.Child
    @Environment(WatchStore.self) private var store

    private struct DoseSlot: Identifiable {
        let time: Date
        let medicines: [String]

        var id: Date { time }
    }

    private var slots: [DoseSlot] {
        Dictionary(grouping: child.upcomingDoses) { Int($0.time.timeIntervalSince1970 / 60) }
            .values
            .compactMap { doses in
                doses.first.map { DoseSlot(time: $0.time, medicines: doses.map(\.medicine)) }
            }
            .sorted { $0.time < $1.time }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    FilledProgressCircle(progress: Double(child.dosesLogged) / Double(max(child.dosesDue, 1)),
                                         tint: .green, label: "\(child.dosesLogged)/\(child.dosesDue)")
                        .frame(width: 44, height: 44)
                        .accessibilityElement()
                        .accessibilityLabel("Doses")
                        .accessibilityValue("\(child.dosesLogged) of \(child.dosesDue) logged")

                    Text(medicationStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(slots) { slot in
                Section(slot.time.formatted(date: .omitted, time: .shortened)) {
                    Text(slot.medicines.formatted(.list(type: .and)))
                        .font(.headline)

                    HStack {
                        Button {
                            store.log(patientID: child.id, scheduled: slot.time, taken: false)
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .tint(.gray)
                        .accessibilityLabel("Skip dose")

                        Button {
                            store.log(patientID: child.id, scheduled: slot.time, taken: true)
                        } label: {
                            Label("Taken", systemImage: "checkmark")
                        }
                        .tint(.green)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Medication")
    }

    private var medicationStatus: String {
        if child.dosesDue == 0 {
            return "No reminders today"
        }
        return slots.isEmpty ? "All logged" : "\(slots.count) times to go"
    }
}

private struct VisitView: View {
    let child: WidgetSnapshot.Child

    var body: some View {
        ScrollView {
            if let visit = child.nextVisit, visit.date > .now.addingTimeInterval(-3600) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        visit.isTelehealth ? "Telehealth" : "Next Visit",
                        systemImage: visit.isTelehealth ? "video.fill" : "calendar"
                    )
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)

                    Text(visit.date, format: .dateTime.weekday(.wide).day().month())
                        .font(.footnote)
                    Text(visit.date, format: .dateTime.hour().minute())
                        .font(.system(.title, design: .rounded).bold())
                    Text(visit.title)
                        .font(.headline)

                    if let location = visit.location {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(visit.department)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView("No upcoming visits", systemImage: "calendar")
            }
        }
        .navigationTitle("Visit")
    }
}

private struct UpdatesView: View {
    let child: WidgetSnapshot.Child

    var body: some View {
        List {
            Label {
                VStack(alignment: .leading) {
                    Text("Messages")
                    Text(child.unreadMessages == 0 ? "No unread messages" : "\(child.unreadMessages) unread")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "message.fill")
                    .foregroundStyle(WatchColors.teal)
            }

            Label {
                VStack(alignment: .leading) {
                    Text("Test Results")
                    Text(child.newResults == 0 ? "No new results" : "\(child.newResults) new")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "cross.case.fill")
                    .foregroundStyle(.purple)
            }

            Text("Open myRCH on iPhone to read messages and results.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Updates")
    }
}

private struct MedicalIDView: View {
    let child: WidgetSnapshot.Child

    var body: some View {
        List {
            Section("UR Number") {
                if let urNumber = child.urNumber {
                    Text(urNumber)
                        .font(.system(.title3, design: .monospaced).bold())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .accessibilityLabel(urNumber.map(String.init).joined(separator: " "))
                } else {
                    Text("Open Home on iPhone to load it")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Allergies") {
                if child.allergies.isEmpty, child.allergiesKnown != true {
                    // Not read from the record: say so, never "none".
                    Text("Not available in the app yet. Check with the care team.")
                        .foregroundStyle(.orange)
                } else if child.allergies.isEmpty {
                    Text("No allergies recorded")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(child.allergies, id: \.self) { allergy in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(allergy.substance)
                                .font(.headline)
                            Text(allergy.reaction)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(child.name)
    }
}

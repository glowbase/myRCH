import AppIntents
import SwiftUI
import UIKit
import WidgetKit

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    /// Chosen in Edit Widget; nil follows the child open in the app.
    var childID: String? = nil
    /// The child this widget shows.
    var child: WidgetSnapshot.Child? { snapshot?.child(childID) }
    /// "Open myRCH to set up" rather than "nothing to show".
    var isSetUp: Bool { snapshot?.children.isEmpty == false }

    /// Visits still to come at this entry's time, allowing an hour after
    /// the start so a visit in progress stays up.
    var upcomingVisits: [WidgetSnapshot.Visit] {
        (child?.visits ?? []).filter { $0.date > date.addingTimeInterval(-3600) }
    }
}

/// Every widget's provider: the snapshot for the chosen child, with an
/// entry at each upcoming dose and visit so the widget moves on by itself.
/// The app reloads widgets whenever the data changes.
struct SnapshotProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .sample)
    }

    func snapshot(for configuration: SelectChildIntent, in context: Context) async -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: context.isPreview ? .sample : WidgetSnapshot.load(),
                      childID: configuration.child?.id)
    }

    func timeline(for configuration: SelectChildIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        let snapshot = WidgetSnapshot.load()
        let child = snapshot?.child(configuration.child?.id)
        var dates = [Date.now]
        dates += (child?.upcomingDoses.map(\.time) ?? []).filter { $0 > .now }
        // At each visit's start, and an hour later when it drops off.
        for visit in child?.visits ?? [] {
            dates += [visit.date, visit.date.addingTimeInterval(3600)].filter { $0 > .now }
        }
        let entries = Set(dates).sorted().map {
            SnapshotEntry(date: $0, snapshot: snapshot, childID: configuration.child?.id)
        }
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        return Timeline(entries: entries, policy: .after(midnight))
    }
}

extension WidgetSnapshot {
    static let sample: WidgetSnapshot = {
        let visits = [
            Visit(title: "Nephrology Review", department: "Nephrology Clinic",
                  date: .now.addingTimeInterval(3 * 86_400), isTelehealth: false,
                  location: "Specialist Clinics, Desk A1", desk: "Specialist Clinics Desk A1"),
            Visit(title: "Telehealth Check-in", department: "Dermatology",
                  date: .now.addingTimeInterval(12 * 86_400), isTelehealth: true, location: nil),
            Visit(title: "Review", department: "Respiratory Medicine",
                  date: .now.addingTimeInterval(30 * 86_400), isTelehealth: false,
                  location: "Specialist Clinics, Desk A1", desk: "Specialist Clinics Desk A1")
        ]
        let child = Child(id: "sample", name: "Sallie", urNumber: "10000001",
                          nextVisit: visits.first, upcomingVisits: visits,
                          upcomingDoses: [Dose(medicine: "Hypersal", time: .now.addingTimeInterval(3600))],
                          dosesDue: 3, dosesLogged: 1,
                          allergies: [Allergy(substance: "Peanut", reaction: "Anaphylaxis")],
                          unreadMessages: 1, newResults: 2, updated: .now)
        return WidgetSnapshot(children: [child.id: child], activeChildID: child.id, showsAllergiesOnLockScreen: true)
    }()
}

/// The app's colours (`Theme`), with each section in its Browse colour so
/// a widget matches the screen it opens. Lighter shades in dark mode.
enum WidgetColors {
    static let teal = Color(red: 0.13, green: 0.62, blue: 0.74)
    static let visits = shade(0.88, 0.32, 0.24, dark: 1.00, 0.52, 0.44)
    static let testResults = shade(0.36, 0.35, 0.86, dark: 0.60, 0.60, 1.00)
    static let medication = shade(0.00, 0.50, 0.78, dark: 0.30, 0.74, 0.98)
    static let allergies = shade(0.86, 0.42, 0.06, dark: 1.00, 0.64, 0.30)
    static let messages = shade(0.10, 0.46, 0.92, dark: 0.42, 0.66, 1.00)
    static let medicalID = shade(0.80, 0.16, 0.20, dark: 1.00, 0.46, 0.46)
    static let green = Color(red: 0.20, green: 0.66, blue: 0.33)

    private static func shade(_ r: Double, _ g: Double, _ b: Double,
                              dark dr: Double, _ dg: Double, _ db: Double) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: dr, green: dg, blue: db, alpha: 1)
                : UIColor(red: r, green: g, blue: b, alpha: 1)
        })
    }
}

/// Today's doses as a filled circle, like the app's `DoseCircle`: a pie of
/// logged doses over a pale circle. Solid with a tick once all are logged.
private struct FilledProgressCircle: View {
    /// Share of today's doses logged, 0...1.
    let progress: Double
    let tint: Color
    var label: String? = nil
    var font: Font = .caption.weight(.bold)

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.18))
            PieWedge(end: progress).fill(tint)
            if let label {
                Text(label)
                    .font(font)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(progress >= 0.999 ? Color.white : .primary)
            } else if progress >= 0.999 {
                Image(systemName: "checkmark")
                    .font(font)
                    .foregroundStyle(.white)
            }
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

private struct EmptyWidget: View {
    let symbol: String
    let text: String
    var tint: Color = WidgetColors.teal

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title2).foregroundStyle(tint)
            Text(text).font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }
}

/// A widget's small coloured heading, e.g. "Next Visit" in the Visits colour.
private struct WidgetHeading: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
    }
}

/// A visit's day as a small calendar leaf: weekday over the date, in the
/// Visits colour, as in the app's visits list.
private struct VisitDayBlock: View {
    let date: Date

    var body: some View {
        VStack(spacing: 0) {
            Text(date, format: .dateTime.weekday(.abbreviated))
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(WidgetColors.visits)
            Text(date, format: .dateTime.day())
                .font(.system(.title2, design: .rounded).bold())
            Text(date, format: .dateTime.month(.abbreviated))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 40)
    }
}

/// "In 3 days", "Tomorrow", "Today" or "Now", counted in calendar days.
private func visitCountdown(to date: Date, from now: Date) -> String {
    let calendar = Calendar.current
    if date <= now { return "Now" }
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                       to: calendar.startOfDay(for: date)).day ?? 0
    switch days {
    case 0: return "Today"
    case 1: return "Tomorrow"
    default: return "In \(days) days"
    }
}

// MARK: - Next visit

struct NextVisitView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content.widgetURL(DeepLink.visitURL(child: entry.child?.id, id: entry.upcomingVisits.first?.id))
    }

    @ViewBuilder
    private var content: some View {
        if let visit = entry.upcomingVisits.first {
            switch family {
            case .accessoryInline:
                Label {
                    Text("\(visit.title) · \(visit.date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                } icon: {
                    Image(systemName: visit.isTelehealth ? "video.fill" : "calendar")
                }
                .privacySensitive()
            case .accessoryCircular:
                countdown(visit)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Label("Next Visit", systemImage: visit.isTelehealth ? "video.fill" : "calendar")
                        .font(.caption2.weight(.semibold))
                    Text(visit.title).font(.headline).lineLimit(1)
                    Text(visit.date, format: .dateTime.weekday(.abbreviated).day().month().hour().minute())
                        .font(.caption)
                    if let desk = visit.desk {
                        Text(desk).font(.caption2).lineLimit(1)
                    }
                }
                .privacySensitive()
            case .systemMedium:
                medium(visit)
            default:
                small(visit)
            }
        } else {
            switch family {
            case .accessoryInline:
                Label("No upcoming visits", systemImage: "calendar")
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "calendar").font(.title3)
                }
            default:
                EmptyWidget(symbol: "calendar", text: entry.isSetUp ? "No upcoming visits" : "Open myRCH to set up",
                            tint: WidgetColors.visits)
            }
        }
    }

    /// Days to go, or the time on the day itself.
    private func countdown(_ visit: WidgetSnapshot.Visit) -> some View {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: entry.date),
                                           to: calendar.startOfDay(for: visit.date)).day ?? 0
        return ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: -2) {
                Image(systemName: visit.isTelehealth ? "video.fill" : "calendar")
                    .font(.caption2)
                if days <= 0 {
                    Text(visit.date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                        .font(.system(.headline, design: .rounded))
                        .minimumScaleFactor(0.6)
                } else {
                    Text("\(days)")
                        .font(.system(.title3, design: .rounded).bold())
                    Text(days == 1 ? "day" : "days")
                        .font(.caption2)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Next visit \(visitCountdown(to: visit.date, from: entry.date).lowercased())")
    }

    private func small(_ visit: WidgetSnapshot.Visit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeading(title: visit.isTelehealth ? "Telehealth" : "Next Visit",
                          symbol: visit.isTelehealth ? "video.fill" : "calendar", tint: WidgetColors.visits)
            Spacer(minLength: 0)
            Text(visit.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(visit.date, format: .dateTime.hour().minute())
                .font(.system(.title, design: .rounded).bold())
                .minimumScaleFactor(0.7)
            Text(visit.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .privacySensitive()
    }

    /// The day as a calendar leaf, then what, when and where to check in.
    private func medium(_ visit: WidgetSnapshot.Visit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                WidgetHeading(title: visit.isTelehealth ? "Telehealth" : "Next Visit",
                              symbol: visit.isTelehealth ? "video.fill" : "calendar", tint: WidgetColors.visits)
                Spacer()
                Text(visitCountdown(to: visit.date, from: entry.date))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 12) {
                VisitDayBlock(date: visit.date)
                VStack(alignment: .leading, spacing: 2) {
                    Text(visit.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(visit.date, format: .dateTime.hour().minute())
                        .font(.subheadline.weight(.semibold))
                    Text(visit.department)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let desk = visit.desk {
                        Label(desk, systemImage: "mappin.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WidgetColors.visits)
                            .lineLimit(1)
                    } else if visit.isTelehealth {
                        Label("The clinician will call you", systemImage: "phone.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .privacySensitive()
    }
}

struct NextVisitWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "NextVisit", intent: SelectChildIntent.self, provider: SnapshotProvider()) {
            NextVisitView(entry: $0).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next Visit")
        .description("The next appointment at the hospital, with where to check in.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - Upcoming visits

struct UpcomingVisitsView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var limit: Int { family == .systemLarge ? 5 : 2 }

    var body: some View {
        content.widgetURL(DeepLink.visitsURL(child: entry.child?.id))
    }

    @ViewBuilder
    private var content: some View {
        let visits = Array(entry.upcomingVisits.prefix(limit))
        if visits.isEmpty {
            EmptyWidget(symbol: "calendar", text: entry.isSetUp ? "No upcoming visits" : "Open myRCH to set up",
                        tint: WidgetColors.visits)
        } else {
            VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 8) {
                HStack {
                    WidgetHeading(title: entry.child.map { "\($0.name)'s Visits" } ?? "Upcoming Visits",
                                  symbol: "calendar", tint: WidgetColors.visits)
                    Spacer()
                    if entry.upcomingVisits.count > limit {
                        Text("+\(entry.upcomingVisits.count - limit) more")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(visits.enumerated()), id: \.offset) { index, visit in
                    if index > 0 { Divider() }
                    Link(destination: DeepLink.visitURL(child: entry.child?.id, id: visit.id) ?? URL(filePath: "/")) {
                        row(visit)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .privacySensitive()
        }
    }

    private func row(_ visit: WidgetSnapshot.Visit) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VisitDayBlock(date: visit.date)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if visit.isTelehealth {
                        Image(systemName: "video.fill").font(.caption2)
                    }
                    Text(visit.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                Text("\(visit.date.formatted(.dateTime.hour().minute())) · \(visit.department)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if family == .systemLarge, let desk = visit.desk {
                    Label(desk, systemImage: "mappin.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WidgetColors.visits)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct UpcomingVisitsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "UpcomingVisits", intent: SelectChildIntent.self, provider: SnapshotProvider()) {
            UpcomingVisitsView(entry: $0).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Upcoming Visits")
        .description("The next few appointments. Tap one to open it.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Medication progress

struct MedicationView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var next: WidgetSnapshot.Dose? {
        entry.child?.upcomingDoses.first { $0.time > entry.date.addingTimeInterval(-3600) }
    }

    var body: some View {
        content.widgetURL(DeepLink.medicationURL(child: entry.child?.id))
    }

    @ViewBuilder
    private var content: some View {
        if let child = entry.child, child.dosesDue > 0 {
            let progress = Double(child.dosesLogged) / Double(max(child.dosesDue, 1))
            switch family {
            case .accessoryCircular:
                Gauge(value: progress) {
                    Image(systemName: "pills.fill")
                } currentValueLabel: {
                    Text("\(child.dosesLogged)/\(child.dosesDue)")
                }
                .gaugeStyle(.accessoryCircularCapacity)
            case .systemLarge:
                // StandBy and the bedside: a big filled circle.
                VStack(spacing: 14) {
                    WidgetHeading(title: "\(child.name)'s Medication", symbol: "pills.fill", tint: WidgetColors.medication)
                        .font(.headline)
                    FilledProgressCircle(progress: progress, tint: WidgetColors.green,
                                         label: "\(child.dosesLogged)/\(child.dosesDue)",
                                         font: .system(.largeTitle, design: .rounded).bold())
                        .frame(width: 130, height: 130)
                        .frame(height: 150)
                    if let next {
                        Text("Next: \(next.medicine) at \(next.time.formatted(date: .omitted, time: .shortened))")
                            .font(.subheadline)
                    } else {
                        Text("All done today").font(.subheadline)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .privacySensitive()
            default:
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        WidgetHeading(title: "Medication", symbol: "pills.fill", tint: WidgetColors.medication)
                        Spacer()
                        FilledProgressCircle(progress: progress, tint: WidgetColors.medication,
                                             font: .system(size: 11, weight: .bold))
                            .frame(width: 24, height: 24)
                    }
                    Spacer(minLength: 0)
                    if let next {
                        Text("Next dose").font(.caption).foregroundStyle(.secondary)
                        Text(next.time, format: .dateTime.hour().minute())
                            .font(.system(.title, design: .rounded).bold())
                        Text(next.medicine).font(.caption.weight(.semibold)).lineLimit(1)
                    } else {
                        Text("All done today")
                            .font(.system(.title3, design: .rounded).bold())
                        Text("\(child.dosesLogged) of \(child.dosesDue) doses logged")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .privacySensitive()
            }
        } else {
            EmptyWidget(symbol: "pills", text: entry.isSetUp ? "No reminders set" : "Open myRCH to set up",
                        tint: WidgetColors.medication)
        }
    }
}

struct MedicationWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Medication", intent: SelectChildIntent.self, provider: SnapshotProvider()) {
            MedicationView(entry: $0).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Medication")
        .description("Today's doses logged, and the next one due.")
        .supportedFamilies([.systemSmall, .systemLarge, .accessoryCircular])
    }
}

// MARK: - Next dose, with Taken and Skip

/// Skip and Taken for one dose time, shared by Next Dose and Today.
private struct DoseButtons: View {
    let patientID: String
    let time: Date

    var body: some View {
        HStack(spacing: 6) {
            Button(intent: LogDoseIntent(patientID: patientID, scheduled: time, taken: false)) {
                Text("Skip").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Button(intent: LogDoseIntent(patientID: patientID, scheduled: time, taken: true)) {
                Text("Taken").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WidgetColors.medication)
        }
        .font(.caption.weight(.semibold))
        .controlSize(.small)
    }
}

struct NextDoseView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    /// Taps outside the buttons open that dose's logging sheet, or the
    /// Medication page when nothing's due.
    private var link: URL? {
        if let child = entry.child, let slot = child.nextSlot {
            return DeepLink.doseURL(patientID: child.id, time: slot.time)
        }
        return DeepLink.medicationURL(child: entry.child?.id)
    }

    var body: some View {
        content.widgetURL(link)
    }

    @ViewBuilder
    private var content: some View {
        if let child = entry.child, let slot = child.nextSlot {
            let names = slot.medicines.formatted(.list(type: .and))
            let time = slot.time.formatted(date: .omitted, time: .shortened)
            switch family {
            case .accessoryInline:
                Label("\(names) · \(time)", systemImage: "pills.fill")
                    .privacySensitive()
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Label("\(child.name)'s Next Dose", systemImage: "pills.fill")
                        .font(.caption2.weight(.semibold))
                    Text(time).font(.headline)
                    Text(names).font(.caption).lineLimit(1)
                }
                .privacySensitive()
            default:
                VStack(alignment: .leading, spacing: 6) {
                    WidgetHeading(title: slot.time < entry.date ? "Due Now" : "Next Dose",
                                  symbol: "pills.fill", tint: WidgetColors.medication)
                    Text(time).font(.system(.title2, design: .rounded).bold())
                    Text(names)
                        .font(.caption.weight(.semibold))
                        .lineLimit(family == .systemSmall ? 2 : 1)
                        .privacySensitive()
                    Spacer(minLength: 0)
                    DoseButtons(patientID: child.id, time: slot.time)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else if let child = entry.child, child.dosesDue > 0 {
            switch family {
            case .accessoryInline:
                Label("All doses logged", systemImage: "checkmark.circle.fill")
            default:
                EmptyWidget(symbol: "checkmark.circle.fill", text: "All of today's doses are logged",
                            tint: WidgetColors.green)
            }
        } else {
            switch family {
            case .accessoryInline:
                Label("No doses today", systemImage: "pills")
            default:
                EmptyWidget(symbol: "pills", text: entry.isSetUp ? "No reminders set" : "Open myRCH to set up",
                            tint: WidgetColors.medication)
            }
        }
    }
}

struct NextDoseWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "NextDose", intent: SelectChildIntent.self, provider: SnapshotProvider()) {
            NextDoseView(entry: $0).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next Dose")
        .description("The next medication due, with Taken and Skip buttons.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Today

/// One glance at the child's day: the next dose (with Taken and Skip), the
/// next visit, and what's new on the portal.
struct TodayView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let child = entry.child {
            switch family {
            case .systemLarge: large(child)
            default: medium(child)
            }
        } else {
            EmptyWidget(symbol: "sun.max.fill", text: "Open myRCH to set up")
        }
    }

    /// Dose on the left, visit on the right.
    private func medium(_ child: WidgetSnapshot.Child) -> some View {
        HStack(alignment: .top, spacing: 14) {
            doseColumn(child, showsButtons: false)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            visitColumn
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .privacySensitive()
    }

    private func large(_ child: WidgetSnapshot.Child) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(child.name)'s Day")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Text(entry.date, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            card { doseColumn(child, showsButtons: true) }
            card { visitColumn }
            card { whatsNew(child) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .privacySensitive()
    }

    @ViewBuilder
    private func doseColumn(_ child: WidgetSnapshot.Child, showsButtons: Bool) -> some View {
        Link(destination: doseLink(child) ?? URL(filePath: "/")) {
            VStack(alignment: .leading, spacing: 3) {
                if let slot = child.nextSlot {
                    WidgetHeading(title: slot.time < entry.date ? "Due Now" : "Next Dose",
                                  symbol: "pills.fill", tint: WidgetColors.medication)
                    Text(slot.time, format: .dateTime.hour().minute())
                        .font(.system(.title2, design: .rounded).bold())
                    Text(slot.medicines.formatted(.list(type: .and)))
                        .font(.caption.weight(.semibold))
                        .lineLimit(showsButtons ? 1 : 2)
                } else {
                    WidgetHeading(title: "Medication", symbol: "pills.fill", tint: WidgetColors.medication)
                    Text(child.dosesDue > 0 ? "All done" : "None today")
                        .font(.system(.title3, design: .rounded).bold())
                    if child.dosesDue > 0 {
                        Text("\(child.dosesLogged) of \(child.dosesDue) doses logged")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        if showsButtons, let slot = child.nextSlot {
            DoseButtons(patientID: child.id, time: slot.time)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var visitColumn: some View {
        let visit = entry.upcomingVisits.first
        Link(destination: DeepLink.visitURL(child: entry.child?.id, id: visit?.id) ?? URL(filePath: "/")) {
            VStack(alignment: .leading, spacing: 3) {
                WidgetHeading(title: visit?.isTelehealth == true ? "Telehealth" : "Next Visit",
                              symbol: visit?.isTelehealth == true ? "video.fill" : "calendar",
                              tint: WidgetColors.visits)
                if let visit {
                    Text(visitCountdown(to: visit.date, from: entry.date))
                        .font(.system(.title3, design: .rounded).bold())
                    Text("\(visit.title), \(visit.date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                    if family == .systemLarge, let desk = visit.desk {
                        Label(desk, systemImage: "mappin.circle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WidgetColors.visits)
                            .lineLimit(1)
                    }
                } else {
                    Text("None booked")
                        .font(.system(.title3, design: .rounded).bold())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func whatsNew(_ child: WidgetSnapshot.Child) -> some View {
        Link(destination: DeepLink.whatsNewURL(child: child.id) ?? URL(filePath: "/")) {
            HStack(spacing: 16) {
                count(child.newResults, child.newResults == 1 ? "new result" : "new results",
                      symbol: "testtube.2", tint: WidgetColors.testResults)
                count(child.unreadMessages, child.unreadMessages == 1 ? "message" : "messages",
                      symbol: "bubble.left.and.bubble.right.fill", tint: WidgetColors.messages)
                Spacer(minLength: 0)
            }
        }
    }

    private func count(_ value: Int, _ label: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.caption).foregroundStyle(tint)
            Text("\(value)").font(.system(.title3, design: .rounded).bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.quaternary, in: .rect(cornerRadius: 14))
    }

    private func doseLink(_ child: WidgetSnapshot.Child) -> URL? {
        if let slot = child.nextSlot { return DeepLink.doseURL(patientID: child.id, time: slot.time) }
        return DeepLink.medicationURL(child: child.id)
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Today", intent: SelectChildIntent.self, provider: SnapshotProvider()) {
            TodayView(entry: $0).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("The next dose and visit together. The large size adds Taken and Skip, and what's new.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - UR number

struct URNumberView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let child = entry.child, let ur = child.urNumber {
            VStack(alignment: .leading, spacing: family == .accessoryRectangular ? 0 : 4) {
                Label("\(child.name) · UR", systemImage: "staroflife.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(family == .accessoryRectangular ? Color.primary : WidgetColors.medicalID)
                Text(ur)
                    .font(.system(family == .accessoryRectangular ? .title2 : .title, design: .monospaced).bold())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if family != .accessoryRectangular {
                    Spacer(minLength: 0)
                    Text("Tap for Medical ID").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(DeepLink.medicalIDURL(child: child.id))
        } else {
            EmptyWidget(symbol: "staroflife",
                        text: entry.isSetUp ? "Open Home to load the UR number" : "Open myRCH to set up",
                        tint: WidgetColors.medicalID)
        }
    }
}

struct URNumberWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "URNumber", intent: SelectChildIntent.self, provider: SnapshotProvider()) {
            URNumberView(entry: $0).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("UR Number")
        .description("The hospital UR number, large, for check-in. Tap for the Medical ID.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

// MARK: - Allergy alert

/// Deliberately readable when locked, like Medical ID for a first
/// responder, so it shows nothing until turned on in the app's Settings.
struct AllergyView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.snapshot?.showsAllergiesOnLockScreen != true {
            EmptyWidget(symbol: "allergens", text: "Turn on in myRCH Settings", tint: WidgetColors.allergies)
        } else if let child = entry.child, child.allergies.isEmpty, child.allergiesKnown != true {
            // Not read from the record: say so, never "no known allergies".
            VStack(alignment: .leading, spacing: 2) {
                Label("\(child.name)'s Allergies", systemImage: "questionmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(family == .accessoryRectangular ? Color.primary : WidgetColors.allergies)
                Text("Not available in the app yet")
                    .font(family == .accessoryRectangular ? .caption : .subheadline.weight(.semibold))
                    .lineLimit(2)
                if family != .accessoryRectangular { Spacer(minLength: 0) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(DeepLink.medicalIDURL(child: child.id))
        } else if let child = entry.child {
            let none = child.allergies.isEmpty
            VStack(alignment: .leading, spacing: 2) {
                Label(none ? "\(child.name): no known allergies" : "\(child.name)'s Allergies",
                      systemImage: none ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(family == .accessoryRectangular
                                     ? Color.primary : (none ? WidgetColors.green : WidgetColors.allergies))
                ForEach(child.allergies.prefix(family == .accessoryRectangular ? 2 : 4), id: \.self) { allergy in
                    Text(allergy.reaction.isEmpty ? allergy.substance : "\(allergy.substance) – \(allergy.reaction)")
                        .font(family == .accessoryRectangular ? .caption : .subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                if family != .accessoryRectangular { Spacer(minLength: 0) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(DeepLink.medicalIDURL(child: child.id))
        } else {
            EmptyWidget(symbol: "allergens", text: "Open myRCH to set up", tint: WidgetColors.allergies)
        }
    }
}

struct AllergyWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Allergies", intent: SelectChildIntent.self, provider: SnapshotProvider()) {
            AllergyView(entry: $0).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Allergy Alert")
        .description("Allergies, readable without unlocking. Turn on in myRCH Settings.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

// MARK: - What's new

struct WhatsNewView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content.widgetURL(DeepLink.whatsNewURL(child: entry.child?.id))
    }

    @ViewBuilder
    private var content: some View {
        if let child = entry.child {
            let total = child.newResults + child.unreadMessages
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: "bell.fill").font(.caption)
                        Text("\(total)").font(.headline)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(total) new")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Label("\(child.name) · What's New", systemImage: "bell.badge.fill")
                        .font(.caption2.weight(.semibold))
                    Text(total == 0 ? "All caught up" : "\(child.newResults) \(child.newResults == 1 ? "result" : "results"), \(child.unreadMessages) \(child.unreadMessages == 1 ? "message" : "messages")")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("As of \(child.updated.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                }
            case .systemMedium:
                VStack(alignment: .leading, spacing: 8) {
                    WidgetHeading(title: "What's New for \(child.name)", symbol: "bell.badge.fill",
                                  tint: WidgetColors.messages)
                    HStack(spacing: 10) {
                        tile(child.newResults, child.newResults == 1 ? "New result" : "New results",
                             symbol: "testtube.2", tint: WidgetColors.testResults)
                        tile(child.unreadMessages, child.unreadMessages == 1 ? "Message" : "Messages",
                             symbol: "bubble.left.and.bubble.right.fill", tint: WidgetColors.messages)
                    }
                    Text("As of \(child.updated.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            default:
                VStack(alignment: .leading, spacing: 6) {
                    WidgetHeading(title: "What's New", symbol: "bell.badge.fill", tint: WidgetColors.messages)
                    Spacer(minLength: 0)
                    row("\(child.newResults)", child.newResults == 1 ? "new result" : "new results",
                        "testtube.2", tint: WidgetColors.testResults)
                    row("\(child.unreadMessages)", child.unreadMessages == 1 ? "message" : "messages",
                        "bubble.left.and.bubble.right.fill", tint: WidgetColors.messages)
                    // Only as fresh as the last time the app loaded Home.
                    Text("As of \(child.updated.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else {
            EmptyWidget(symbol: "bell", text: "Open myRCH to set up", tint: WidgetColors.messages)
        }
    }

    private func row(_ count: String, _ label: String, _ symbol: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.caption).foregroundStyle(tint).frame(width: 18)
            Text(count).font(.system(.title3, design: .rounded).bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// A count in its section's colour, e.g. results in indigo.
    private func tile(_ count: Int, _ label: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: symbol).font(.subheadline).foregroundStyle(tint)
            Text("\(count)").font(.system(.title, design: .rounded).bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: .rect(cornerRadius: 14))
    }
}

struct WhatsNewWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WhatsNew", intent: SelectChildIntent.self, provider: SnapshotProvider()) {
            WhatsNewView(entry: $0).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("What's New")
        .description("New results and unread messages, as of the last time myRCH was opened.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Control Centre

/// Opens the Medical ID at full brightness, for check-in.
struct ShowURNumberControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ShowURNumber") {
            ControlWidgetButton(action: OpenURLIntent(DeepLink.medicalIDURL(child: nil) ?? URL(filePath: "/"))) {
                Label("UR Number", systemImage: "staroflife.fill")
            }
        }
        .displayName("Show UR Number")
        .description("Opens the Medical ID with the UR number, at full brightness.")
    }
}

/// Marks the next dose due today as taken.
struct LogNextDoseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LogNextDose") {
            ControlWidgetButton(action: LogNextDoseIntent()) {
                Label("Log Next Dose", systemImage: "pills.fill")
            }
        }
        .displayName("Log Next Dose")
        .description("Marks the next medication due today as taken.")
    }
}

#Preview(as: .systemSmall) {
    NextDoseWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .sample)
}

#Preview(as: .systemLarge) {
    TodayWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .sample)
}

#Preview(as: .systemMedium) {
    UpcomingVisitsWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .sample)
}

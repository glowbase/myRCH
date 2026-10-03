import AppIntents
import SwiftUI
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
        if let visit = child?.nextVisit?.date, visit > .now { dates.append(visit) }
        let entries = Set(dates).sorted().map {
            SnapshotEntry(date: $0, snapshot: snapshot, childID: configuration.child?.id)
        }
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        return Timeline(entries: entries, policy: .after(midnight))
    }
}

extension WidgetSnapshot {
    static let sample: WidgetSnapshot = {
        let child = Child(id: "sample", name: "Sallie", urNumber: "10000001",
                          nextVisit: Visit(title: "Nephrology Review", department: "Nephrology Clinic",
                                           date: .now.addingTimeInterval(3 * 86_400), isTelehealth: false,
                                           location: "Specialist Clinics, Desk A1"),
                          upcomingDoses: [Dose(medicine: "Hypersal", time: .now.addingTimeInterval(3600))],
                          dosesDue: 3, dosesLogged: 1,
                          allergies: [Allergy(substance: "Peanut", reaction: "Anaphylaxis")],
                          unreadMessages: 1, newResults: 2, updated: .now)
        return WidgetSnapshot(children: [child.id: child], activeChildID: child.id, showsAllergiesOnLockScreen: true)
    }()
}

/// Matches the app's colours (`Theme`).
enum WidgetColors {
    static let teal = Color(red: 0.13, green: 0.62, blue: 0.74)
    static let medication = Color(red: 0.0, green: 0.52, blue: 0.74)
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

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title2).foregroundStyle(WidgetColors.teal)
            Text(text).font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Next visit

struct NextVisitView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content.widgetURL(DeepLink.visitURL(child: entry.child?.id, id: entry.child?.nextVisit?.id))
    }

    @ViewBuilder
    private var content: some View {
        if let visit = entry.child?.nextVisit, visit.date > entry.date.addingTimeInterval(-3600) {
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Label("Next Visit", systemImage: "calendar")
                        .font(.caption2.weight(.semibold))
                    Text(visit.title).font(.headline).lineLimit(1)
                    Text(visit.date, format: .dateTime.weekday(.abbreviated).day().month().hour().minute())
                        .font(.caption)
                }
                .privacySensitive()
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Label(visit.isTelehealth ? "Telehealth" : "Next Visit",
                          systemImage: visit.isTelehealth ? "video.fill" : "calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                    Spacer(minLength: 0)
                    Text(visit.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(visit.date, format: .dateTime.hour().minute())
                        .font(.system(.title, design: .rounded).bold())
                    Text(visit.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(family == .systemSmall ? 1 : 2)
                    if family != .systemSmall {
                        Text(visit.location ?? visit.department)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .privacySensitive()
            }
        } else {
            EmptyWidget(symbol: "calendar", text: entry.isSetUp ? "No upcoming visits" : "Open myRCH to set up")
        }
    }
}

struct NextVisitWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "NextVisit", intent: SelectChildIntent.self, provider: SnapshotProvider()) {
            NextVisitView(entry: $0).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next Visit")
        .description("The next appointment at the hospital.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
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
                    Label("\(child.name)'s Medication", systemImage: "pills.fill")
                        .font(.headline)
                        .foregroundStyle(WidgetColors.medication)
                    FilledProgressCircle(progress: progress, tint: .green,
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
                        Label("Medication", systemImage: "pills.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WidgetColors.medication)
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
            EmptyWidget(symbol: "pills", text: entry.isSetUp ? "No reminders set" : "Open myRCH to set up")
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
                    Label(slot.time < entry.date ? "Due Now" : "Next Dose", systemImage: "pills.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WidgetColors.medication)
                    Text(time).font(.system(.title2, design: .rounded).bold())
                    Text(names)
                        .font(.caption.weight(.semibold))
                        .lineLimit(family == .systemSmall ? 2 : 1)
                        .privacySensitive()
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        Button(intent: LogDoseIntent(patientID: child.id, scheduled: slot.time, taken: false)) {
                            Text("Skip").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Button(intent: LogDoseIntent(patientID: child.id, scheduled: slot.time, taken: true)) {
                            Text("Taken").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(WidgetColors.medication)
                    }
                    .font(.caption.weight(.semibold))
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else if let child = entry.child, child.dosesDue > 0 {
            switch family {
            case .accessoryInline:
                Label("All doses logged", systemImage: "checkmark.circle.fill")
            default:
                EmptyWidget(symbol: "checkmark.circle.fill", text: "All of today's doses are logged")
            }
        } else {
            switch family {
            case .accessoryInline:
                Label("No doses today", systemImage: "pills")
            default:
                EmptyWidget(symbol: "pills", text: entry.isSetUp ? "No reminders set" : "Open myRCH to set up")
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

// MARK: - UR number

struct URNumberView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let child = entry.child, let ur = child.urNumber {
            VStack(alignment: .leading, spacing: family == .accessoryRectangular ? 0 : 4) {
                Label("\(child.name) · UR", systemImage: "staroflife.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(family == .accessoryRectangular ? Color.primary : Color.red)
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
                        text: entry.isSetUp ? "Open Home to load the UR number" : "Open myRCH to set up")
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
            EmptyWidget(symbol: "allergens", text: "Turn on in myRCH Settings")
        } else if let child = entry.child, child.allergies.isEmpty, child.allergiesKnown != true {
            // Not read from the record: say so, never "no known allergies".
            VStack(alignment: .leading, spacing: 2) {
                Label("\(child.name)'s Allergies", systemImage: "questionmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(family == .accessoryRectangular ? Color.primary : Color.orange)
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
                    .foregroundStyle(family == .accessoryRectangular ? Color.primary : (none ? Color.green : Color.orange))
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
            EmptyWidget(symbol: "allergens", text: "Open myRCH to set up")
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
            default:
                VStack(alignment: .leading, spacing: 6) {
                    Label("What's New", systemImage: "bell.badge.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WidgetColors.teal)
                    Spacer(minLength: 0)
                    row("\(child.newResults)", child.newResults == 1 ? "new result" : "new results", "testtube.2")
                    row("\(child.unreadMessages)", child.unreadMessages == 1 ? "message" : "messages",
                        "bubble.left.and.bubble.right.fill")
                    // Only as fresh as the last time the app loaded Home.
                    Text("As of \(child.updated.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else {
            EmptyWidget(symbol: "bell", text: "Open myRCH to set up")
        }
    }

    private func row(_ count: String, _ label: String, _ symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.caption).foregroundStyle(.secondary).frame(width: 18)
            Text(count).font(.system(.title3, design: .rounded).bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct WhatsNewWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WhatsNew", intent: SelectChildIntent.self, provider: SnapshotProvider()) {
            WhatsNewView(entry: $0).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("What's New")
        .description("New results and unread messages, as of the last time myRCH was opened.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
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

import SwiftUI
import WidgetKit

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    /// The child this widget shows.
    var child: WidgetSnapshot.Child? { snapshot?.child() }
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .sample : WidgetSnapshot.load()))
    }

    /// One entry now and one at each upcoming dose or visit, so the widget
    /// moves on by itself; the app reloads it whenever the data changes.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        var dates = [Date.now]
        dates += (snapshot?.child()?.upcomingDoses.map(\.time) ?? []).filter { $0 > .now }
        if let visit = snapshot?.child()?.nextVisit?.date, visit > .now { dates.append(visit) }
        let entries = dates.sorted().map { SnapshotEntry(date: $0, snapshot: snapshot) }
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        completion(Timeline(entries: entries, policy: .after(midnight)))
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
        return WidgetSnapshot(children: [child.id: child], activeChildID: child.id)
    }()
}

private let teal = Color(red: 0.13, green: 0.62, blue: 0.74)
/// Matches the app's `Theme.medication`.
private let medicationColor = Color(red: 0.0, green: 0.52, blue: 0.74)

// MARK: - Next visit

struct NextVisitView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
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
                        Text(visit.department).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .privacySensitive()
            }
        } else {
            EmptyWidget(symbol: "calendar", text: entry.snapshot == nil ? "Open myRCH to set up" : "No upcoming visits")
        }
    }
}

struct NextVisitWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextVisit", provider: SnapshotProvider()) { entry in
            NextVisitView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next Visit")
        .description("The next appointment at the hospital.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

// MARK: - Medication

struct MedicationView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var next: WidgetSnapshot.Dose? {
        entry.child?.upcomingDoses.first { $0.time > entry.date.addingTimeInterval(-3600) }
    }

    var body: some View {
        if let snapshot = entry.child, snapshot.dosesDue > 0 {
            let progress = Double(snapshot.dosesLogged) / Double(max(snapshot.dosesDue, 1))
            switch family {
            case .accessoryCircular:
                Gauge(value: progress) {
                    Image(systemName: "pills.fill")
                } currentValueLabel: {
                    Text("\(snapshot.dosesLogged)/\(snapshot.dosesDue)")
                }
                .gaugeStyle(.accessoryCircularCapacity)
            default:
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Medication", systemImage: "pills.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(medicationColor)
                        Spacer()
                        Gauge(value: progress) { EmptyView() }
                            .gaugeStyle(.accessoryCircularCapacity)
                            .tint(medicationColor)
                            .scaleEffect(0.6)
                            .frame(width: 30, height: 30)
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
                        Text("\(snapshot.dosesLogged) of \(snapshot.dosesDue) doses logged")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .privacySensitive()
            }
        } else {
            EmptyWidget(symbol: "pills", text: entry.snapshot == nil ? "Open myRCH to set up" : "No reminders set")
        }
    }
}

struct MedicationWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Medication", provider: SnapshotProvider()) { entry in
            MedicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Medication")
        .description("The next dose due today, and how many are logged.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

private struct EmptyWidget: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title2).foregroundStyle(teal)
            Text(text).font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }
}

#Preview(as: .systemSmall) {
    NextVisitWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .sample)
}

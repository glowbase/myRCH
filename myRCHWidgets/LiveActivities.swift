import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Dose due

struct DoseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DoseActivityAttributes.self) { context in
            DoseLockScreenView(context: context)
                .padding()
                .activityBackgroundTint(Color(.systemBackground).opacity(0.85))
                .widgetURL(DeepLink.doseURL(patientID: context.attributes.patientID, time: context.state.time))
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(context.attributes.childName)", systemImage: "pills.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WidgetColors.medication)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(state.time, format: .dateTime.hour().minute())
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.medicines.formatted(.list(type: .and)))
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DoseButtons(patientID: context.attributes.patientID, time: state.time)
                }
            } compactLeading: {
                Image(systemName: "pills.fill").foregroundStyle(WidgetColors.medication)
            } compactTrailing: {
                Text(state.time, format: .dateTime.hour().minute())
                    .font(.caption2.weight(.semibold))
            } minimal: {
                Image(systemName: "pills.fill").foregroundStyle(WidgetColors.medication)
            }
            .widgetURL(DeepLink.doseURL(patientID: context.attributes.patientID, time: state.time))
        }
    }
}

private struct DoseLockScreenView: View {
    let context: ActivityViewContext<DoseActivityAttributes>

    var body: some View {
        let state = context.state
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(state.time < .now ? "\(context.attributes.childName)'s dose is due"
                                        : "\(context.attributes.childName)'s next dose",
                      systemImage: "pills.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WidgetColors.medication)
                Spacer()
                Text("\(state.logged) of \(state.due) today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(state.time, format: .dateTime.hour().minute())
                    .font(.system(.title, design: .rounded).bold())
                Text(state.medicines.formatted(.list(type: .and)))
                    .font(.headline)
                    .lineLimit(1)
            }
            DoseButtons(patientID: context.attributes.patientID, time: state.time)
        }
    }
}

private struct DoseButtons: View {
    let patientID: String
    let time: Date

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: LogDoseIntent(patientID: patientID, scheduled: time, taken: false)) {
                Label("Skip", systemImage: "xmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Button(intent: LogDoseIntent(patientID: patientID, scheduled: time, taken: true)) {
                Label("Taken", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WidgetColors.medication)
        }
        .font(.subheadline.weight(.semibold))
    }
}

// MARK: - Visit day

struct VisitLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VisitActivityAttributes.self) { context in
            VisitLockScreenView(context: context)
                .padding()
                .activityBackgroundTint(Color(.systemBackground).opacity(0.85))
                .widgetURL(DeepLink.visitURL(child: context.attributes.patientID, id: context.attributes.visitID))
        } dynamicIsland: { context in
            let attributes = context.attributes
            let date = context.state.date
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(attributes.isTelehealth ? "Telehealth" : "Visit",
                          systemImage: attributes.isTelehealth ? "video.fill" : "calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(date: date).font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attributes.title).font(.headline)
                        Text(attributes.location ?? attributes.department)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: attributes.isTelehealth ? "video.fill" : "calendar").foregroundStyle(.red)
            } compactTrailing: {
                Text(date, format: .dateTime.hour().minute()).font(.caption2.weight(.semibold))
            } minimal: {
                Image(systemName: "calendar").foregroundStyle(.red)
            }
            .widgetURL(DeepLink.visitURL(child: attributes.patientID, id: attributes.visitID))
        }
    }
}

private struct VisitLockScreenView: View {
    let context: ActivityViewContext<VisitActivityAttributes>

    var body: some View {
        let attributes = context.attributes
        let date = context.state.date
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(attributes.isTelehealth ? "\(attributes.childName)'s telehealth call"
                                              : "\(attributes.childName)'s visit today",
                      systemImage: attributes.isTelehealth ? "video.fill" : "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                Spacer()
                Countdown(date: date)
                    .font(.subheadline.weight(.semibold))
            }
            HStack(alignment: .firstTextBaseline) {
                Text(date, format: .dateTime.hour().minute())
                    .font(.system(.title, design: .rounded).bold())
                Text(attributes.title)
                    .font(.headline)
                    .lineLimit(1)
            }
            Label(attributes.location ?? attributes.department,
                  systemImage: attributes.isTelehealth ? "phone.fill" : "mappin.and.ellipse")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

/// "in 1:24:10", counting down, then "Now".
private struct Countdown: View {
    let date: Date

    var body: some View {
        if date > .now {
            Text(timerInterval: Date.now...date, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        } else {
            Text("Now")
        }
    }
}

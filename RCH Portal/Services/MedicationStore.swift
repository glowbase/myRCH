import Foundation
import Observation
import UserNotifications

/// The family's own notes, reminder times and dose log for each medication.
/// Kept only on this device, never sent to the portal. Keyed by patient and
/// medication, so each child's data stays separate.
///
/// Reminders work like the Health app's: a notification at each dose time
/// with Taken / Skip actions, and a follow-up 30 minutes later if the dose
/// hasn't been logged. Each dose is its own one-off notification (not a
/// repeating trigger), so logging a dose can cancel just that day's follow-up.
@MainActor
@Observable
final class MedicationStore {
    /// A daily dose time.
    struct Reminder: Identifiable, Hashable, Codable {
        var id = UUID()
        var hour: Int
        var minute: Int

        var date: Date {
            Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
        }
    }

    struct DoseLog: Hashable, Codable {
        enum Status: String, Codable {
            case taken, skipped
        }
        /// The dose time this entry is for, e.g. today at 8:00.
        var scheduled: Date
        var status: Status
        var loggedAt: Date
    }

    /// One scheduled dose on a particular day, with its logged status.
    struct Dose: Identifiable, Hashable {
        var scheduled: Date
        var status: DoseLog.Status?
        var id: Date { scheduled }
    }

    private struct Entry: Codable {
        var notes: [MedicationNote] = []
        var reminders: [Reminder] = []
        var doses: [DoseLog] = []
        /// The notification text, saved so every reminder can be rescheduled
        /// at launch without waiting for the portal.
        var title: String?
        var body: String?

        init() {}

        /// Tolerates files saved before newer fields existed.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            notes = try container.decodeIfPresent([MedicationNote].self, forKey: .notes) ?? []
            reminders = try container.decodeIfPresent([Reminder].self, forKey: .reminders) ?? []
            doses = try container.decodeIfPresent([DoseLog].self, forKey: .doses) ?? []
            title = try container.decodeIfPresent(String.self, forKey: .title)
            body = try container.decodeIfPresent(String.self, forKey: .body)
        }
    }

    static let followUpDelay: TimeInterval = 30 * 60
    static let snoozeDelay: TimeInterval = 10 * 60
    static let categoryID = "MEDICATION_REMINDER"
    /// iOS keeps at most 64 pending notifications per app; leave headroom.
    private static let maxPending = 60
    private static let horizonDays = 30
    private static let idPrefix = "med|"

    private var entries: [String: Entry] = [:]
    @ObservationIgnored private var rescheduleTask: Task<Void, Never>?

    /// Application Support. Protected until the phone is first unlocked after
    /// a restart, not while locked, so a Taken/Skip tapped on the lock screen
    /// can still be saved.
    @ObservationIgnored private let fileURL: URL = {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "medication-notes.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = saved
        }
    }

    static func key(patientID: String, medicationID: String) -> String {
        "\(patientID)|\(medicationID)"
    }

    // MARK: Notes

    func notes(for key: String) -> [MedicationNote] {
        (entries[key]?.notes ?? []).sorted { $0.date > $1.date }
    }

    func addNote(_ text: String, for key: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries[key, default: Entry()].notes.append(MedicationNote(id: UUID(), text: trimmed, date: .now))
        save()
    }

    func deleteNote(_ note: MedicationNote, for key: String) {
        entries[key]?.notes.removeAll { $0.id == note.id }
        save()
    }

    // MARK: Reminders

    func reminders(for key: String) -> [Reminder] {
        (entries[key]?.reminders ?? []).sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    /// Replaces a medication's dose times. `title`/`body` are the
    /// notification's text. Rescheduling is debounced, so dragging a time
    /// picker doesn't queue a job per tick.
    func setReminders(_ reminders: [Reminder], for key: String, title: String, body: String) {
        entries[key, default: Entry()].reminders = reminders
        entries[key]?.title = title
        entries[key]?.body = body
        save()
        refreshNotifications()
    }

    // MARK: Dose log

    /// Today's (or `day`'s) doses for a medication, earliest first.
    func doses(on day: Date = .now, for key: String) -> [Dose] {
        let calendar = Calendar.current
        let logs = entries[key]?.doses ?? []
        return reminders(for: key).compactMap { reminder in
            guard let scheduled = calendar.date(bySettingHour: reminder.hour, minute: reminder.minute,
                                                second: 0, of: day) else { return nil }
            let log = logs.first { abs($0.scheduled.timeIntervalSince(scheduled)) < 60 }
            return Dose(scheduled: scheduled, status: log?.status)
        }
    }

    func log(_ status: DoseLog.Status?, scheduled: Date, for key: String) {
        var logs = entries[key]?.doses ?? []
        logs.removeAll { abs($0.scheduled.timeIntervalSince(scheduled)) < 60 }
        if let status {
            logs.append(DoseLog(scheduled: scheduled, status: status, loggedAt: .now))
        }
        // Three months of history is plenty, and keeps the file small.
        let cutoff = Date.now.addingTimeInterval(-90 * 24 * 3600)
        entries[key, default: Entry()].doses = logs.filter { $0.scheduled > cutoff }
        save()

        // A logged dose needs no follow-up or snooze, and its delivered
        // notification can leave Notification Centre, as in the Health app.
        let prefix = Self.identifierPrefix(key: key, scheduled: scheduled)
        let center = UNUserNotificationCenter.current()
        Task {
            let pending = await center.pendingNotificationRequests().map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.hasPrefix(prefix) })
            let delivered = await center.deliveredNotifications().map(\.request.identifier)
            center.removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.hasPrefix(prefix) })
        }
        refreshNotifications()
    }

    /// "Remind Me in 10 Minutes": a one-off repeat of the same dose.
    func snooze(scheduled: Date, for key: String) {
        guard let entry = entries[key] else { return }
        let fireDate = Date.now.addingTimeInterval(Self.snoozeDelay)
        let request = Self.request(key: key, scheduled: scheduled, fireDate: fireDate, kind: "snooze",
                                   title: entry.title ?? "Medication reminder",
                                   body: entry.body ?? "Time for a medication.")
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    // MARK: Scheduling

    /// Rebuilds the pending notifications from the saved dose times and log.
    /// Call on launch and whenever the app comes back to the foreground, to
    /// keep the 30-day window topped up.
    func refreshNotifications() {
        rescheduleTask?.cancel()
        rescheduleTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await applySchedule()
        }
    }

    private func applySchedule() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        // Snoozes are one-offs the schedule can't rebuild, so leave them.
        center.removePendingNotificationRequests(withIdentifiers: pending.filter {
            $0.hasPrefix(Self.idPrefix) && !$0.hasSuffix("|snooze")
        })

        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        var upcoming: [UNNotificationRequest] = []
        var fireDates: [String: Date] = [:]

        for (key, entry) in entries where !entry.reminders.isEmpty {
            let title = entry.title ?? "Medication reminder"
            let body = entry.body ?? "Time for a medication."
            for offset in 0..<Self.horizonDays {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
                for reminder in entry.reminders {
                    guard let scheduled = calendar.date(bySettingHour: reminder.hour, minute: reminder.minute,
                                                        second: 0, of: day) else { continue }
                    // Already taken or skipped: nothing to remind about.
                    if entry.doses.contains(where: { abs($0.scheduled.timeIntervalSince(scheduled)) < 60 }) { continue }
                    let time = scheduled.formatted(date: .omitted, time: .shortened)
                    let followUp = scheduled.addingTimeInterval(Self.followUpDelay)
                    for (kind, fireDate, text) in [("main", scheduled, body),
                                                   ("followup", followUp, "\(body) The \(time) dose hasn't been logged yet.")]
                    where fireDate > now {
                        let request = Self.request(key: key, scheduled: scheduled, fireDate: fireDate,
                                                   kind: kind, title: title, body: text)
                        upcoming.append(request)
                        fireDates[request.identifier] = fireDate
                    }
                }
            }
        }

        let soonest = upcoming.sorted { fireDates[$0.identifier]! < fireDates[$1.identifier]! }
            .prefix(Self.maxPending)
        for request in soonest {
            try? await center.add(request)
        }
        #if DEBUG
        // Counts and times only, no medication names.
        let next = soonest.first.flatMap { fireDates[$0.identifier] }
        print("↩︎ Reminders: \(soonest.count) scheduled, next \(next?.formatted() ?? "none"), "
              + "permission \(await center.notificationSettings().authorizationStatus.rawValue)")
        #endif
    }

    private static func identifierPrefix(key: String, scheduled: Date) -> String {
        "\(idPrefix)\(key)|\(Int(scheduled.timeIntervalSince1970))|"
    }

    private static func request(key: String, scheduled: Date, fireDate: Date, kind: String,
                                title: String, body: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = kind == "main" ? title : "Follow-up: \(title)"
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryID
        // Gets through Focus modes, like the Health app's reminders. Needs
        // the Time Sensitive Notifications capability (paid developer team).
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = key
        content.userInfo = ["key": key, "scheduled": scheduled.timeIntervalSince1970]
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: identifierPrefix(key: key, scheduled: scheduled) + kind,
                                     content: content, trigger: trigger)
    }

    /// Asks for notification permission the first time; true if allowed.
    func requestNotificationPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// Handles reminder notifications: shows them while the app is open (iOS
/// otherwise drops them) and carries out the Taken / Skip / Snooze actions.
@MainActor
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()
    weak var store: MedicationStore?

    private enum Action {
        static let taken = "TAKEN"
        static let skipped = "SKIPPED"
        static let snooze = "SNOOZE"
    }

    /// Registers the notification buttons. Call once at launch.
    func register(store: MedicationStore) {
        self.store = store
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: MedicationStore.categoryID,
                actions: [
                    UNNotificationAction(identifier: Action.taken, title: "Mark as Taken",
                                         icon: UNNotificationActionIcon(systemImageName: "checkmark.circle")),
                    UNNotificationAction(identifier: Action.skipped, title: "Skip",
                                         icon: UNNotificationActionIcon(systemImageName: "xmark.circle")),
                    UNNotificationAction(identifier: Action.snooze, title: "Remind Me in 10 Minutes",
                                         icon: UNNotificationActionIcon(systemImageName: "clock"))
                ],
                intentIdentifiers: [])
        ])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let key = info["key"] as? String, let stamp = info["scheduled"] as? Double else { return }
        let scheduled = Date(timeIntervalSince1970: stamp)
        let action = response.actionIdentifier
        await MainActor.run {
            guard let store = NotificationPresenter.shared.store else { return }
            switch action {
            case Action.taken: store.log(.taken, scheduled: scheduled, for: key)
            case Action.skipped: store.log(.skipped, scheduled: scheduled, for: key)
            case Action.snooze: store.snooze(scheduled: scheduled, for: key)
            default: break
            }
        }
    }
}

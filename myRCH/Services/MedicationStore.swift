import Foundation
import Observation
import UserNotifications

/// The family's own notes, reminder times and dose log for each medication.
/// Kept only on this device, never sent to the portal. Keyed by patient and
/// medication, so each child's data stays separate.
///
/// Reminders work like the Health app's: one notification per child per dose
/// time, covering every medication due then ("Time for Sam's 8:00 am
/// medications: …"), with Mark All as Taken / Skip All / Snooze actions, and
/// a follow-up 30 minutes later naming whatever still isn't logged. Tapping a
/// reminder opens a sheet to log each medication. Each slot is its own
/// one-off notification (not a repeating trigger), so a day's follow-up can
/// be dropped once everything in it is logged.
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
        /// A dose taken outside the schedule. Optional so logs saved before
        /// this existed still load.
        var isAsNeeded: Bool? = nil

        var isScheduled: Bool { isAsNeeded != true }
    }

    /// One scheduled dose on a particular day, with its logged status.
    struct Dose: Identifiable, Hashable {
        var scheduled: Date
        var status: DoseLog.Status?
        /// When it was logged, for "Taken at 8:12 am".
        var loggedAt: Date? = nil
        var id: Date { scheduled }
    }

    /// Everything due for one child at one time: what a reminder and the
    /// logging sheet cover.
    struct Slot: Identifiable, Hashable {
        let patientID: String
        let scheduled: Date
        var id: String { "\(patientID)|\(Int(scheduled.timeIntervalSince1970))" }
    }

    /// One medication within a slot.
    struct SlotItem: Identifiable, Hashable {
        let key: String
        let name: String
        let status: DoseLog.Status?
        var id: String { key }
    }

    private struct Entry: Codable {
        var notes: [MedicationNote] = []
        var reminders: [Reminder] = []
        var doses: [DoseLog] = []
        /// Saved so reminders and the logging sheet work at launch, without
        /// waiting for the portal. e.g. "Hypersal", "Sam".
        var medicineName: String?
        var childName: String?

        init() {}

        /// Tolerates files saved before newer fields existed (older files
        /// also have title/body, which are no longer used).
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            notes = try container.decodeIfPresent([MedicationNote].self, forKey: .notes) ?? []
            reminders = try container.decodeIfPresent([Reminder].self, forKey: .reminders) ?? []
            doses = try container.decodeIfPresent([DoseLog].self, forKey: .doses) ?? []
            medicineName = try container.decodeIfPresent(String.self, forKey: .medicineName)
            childName = try container.decodeIfPresent(String.self, forKey: .childName)
        }
    }

    /// Every reminder's title. Fixed here, not read from saved entries, so
    /// reminders set up earlier (saved as "Medication reminder") update too.
    static let reminderTitle = "Medication Reminder"
    static let followUpDelay: TimeInterval = 30 * 60
    static let snoozeDelay: TimeInterval = 10 * 60
    static let categoryID = "MEDICATION_REMINDER"
    /// iOS keeps at most 64 pending notifications per app; leave headroom.
    private static let maxPending = 60
    private static let horizonDays = 30
    private static let idPrefix = "med|"

    private var entries: [String: Entry] = [:]
    @ObservationIgnored private var rescheduleTask: Task<Void, Never>?

    /// Set when a reminder is tapped; the app shows the logging sheet for it.
    var openSlot: Slot?

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

    /// The patient part of a key (patient ids contain no "|").
    private static func patientID(of key: String) -> String {
        String(key.prefix { $0 != "|" })
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

    /// Replaces a medication's dose times. Rescheduling is debounced, so
    /// dragging a time picker doesn't queue a job per tick.
    func setReminders(_ reminders: [Reminder], for key: String, medicineName: String, childName: String?) {
        entries[key, default: Entry()].reminders = reminders
        entries[key]?.medicineName = medicineName
        entries[key]?.childName = childName
        save()
        refreshNotifications()
    }

    /// Keeps the names used in reminders current (and fills them in for
    /// reminders set up before names were saved). Only saves on a change.
    func updateNames(for key: String, medicineName: String, childName: String?) {
        guard let entry = entries[key], !entry.reminders.isEmpty,
              entry.medicineName != medicineName || entry.childName != childName else { return }
        entries[key]?.medicineName = medicineName
        entries[key]?.childName = childName
        save()
        refreshNotifications()
    }

    // MARK: Slots

    /// Every medication of this patient due at `slot`'s time that day.
    func items(in slot: Slot) -> [SlotItem] {
        entries.compactMap { key, entry -> SlotItem? in
            guard Self.patientID(of: key) == slot.patientID,
                  let dose = doses(on: slot.scheduled, for: key)
                    .first(where: { abs($0.scheduled.timeIntervalSince(slot.scheduled)) < 60 }) else { return nil }
            return SlotItem(key: key, name: entry.medicineName ?? "Medication", status: dose.status)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The child's first name for a slot, if saved.
    func childName(in slot: Slot) -> String? {
        entries.first { Self.patientID(of: $0.key) == slot.patientID && $0.value.childName != nil }?.value.childName
    }

    /// Logs everything in the slot that isn't logged yet.
    func logAll(_ status: DoseLog.Status, in slot: Slot) {
        for item in items(in: slot) where item.status == nil {
            log(status, scheduled: slot.scheduled, for: item.key)
        }
    }

    // MARK: Dose log

    /// Today's (or `day`'s) doses for a medication, earliest first.
    func doses(on day: Date = .now, for key: String) -> [Dose] {
        let calendar = Calendar.current
        let logs = entries[key]?.doses ?? []
        return reminders(for: key).compactMap { reminder in
            guard let scheduled = calendar.date(bySettingHour: reminder.hour, minute: reminder.minute,
                                                second: 0, of: day) else { return nil }
            let log = logs.first { $0.isScheduled && abs($0.scheduled.timeIntervalSince(scheduled)) < 60 }
            return Dose(scheduled: scheduled, status: log?.status, loggedAt: log?.loggedAt)
        }
    }

    func log(_ status: DoseLog.Status?, scheduled: Date, for key: String) {
        var logs = entries[key]?.doses ?? []
        logs.removeAll { $0.isScheduled && abs($0.scheduled.timeIntervalSince(scheduled)) < 60 }
        if let status {
            logs.append(DoseLog(scheduled: scheduled, status: status, loggedAt: .now))
        }
        // Three months of history is plenty, and keeps the file small.
        let cutoff = Date.now.addingTimeInterval(-90 * 24 * 3600)
        entries[key, default: Entry()].doses = logs.filter { $0.scheduled > cutoff }
        save()

        // Once everything in the slot is logged, its reminder, follow-up and
        // snooze are done with, and can leave Notification Centre, as in the
        // Health app. (A partly logged slot keeps a follow-up for the rest;
        // the reschedule below rebuilds it with only those names.)
        let slot = Slot(patientID: Self.patientID(of: key), scheduled: scheduled)
        if items(in: slot).allSatisfy({ $0.status != nil }) {
            let prefix = Self.identifierPrefix(slot)
            let center = UNUserNotificationCenter.current()
            Task {
                let pending = await center.pendingNotificationRequests().map(\.identifier)
                center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.hasPrefix(prefix) })
                let delivered = await center.deliveredNotifications().map(\.request.identifier)
                center.removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.hasPrefix(prefix) })
            }
        }
        refreshNotifications()
    }

    /// Doses taken outside the schedule on `day`, earliest first.
    func asNeededLogs(on day: Date, for key: String) -> [DoseLog] {
        let calendar = Calendar.current
        return (entries[key]?.doses ?? [])
            .filter { !$0.isScheduled && calendar.isDate($0.scheduled, inSameDayAs: day) }
            .sorted { $0.scheduled < $1.scheduled }
    }

    /// Records an as-needed dose taken at `date`.
    func logAsNeeded(for key: String, at date: Date = .now) {
        entries[key, default: Entry()].doses.append(
            DoseLog(scheduled: date, status: .taken, loggedAt: .now, isAsNeeded: true))
        save()
    }

    /// Undoes an as-needed dose logged by mistake.
    func removeAsNeeded(_ log: DoseLog, for key: String) {
        entries[key]?.doses.removeAll { !$0.isScheduled && $0.loggedAt == log.loggedAt }
        save()
    }

    /// "Remind Me in 10 Minutes": a one-off repeat for what's still unlogged.
    func snooze(_ slot: Slot) {
        let names = items(in: slot).filter { $0.status == nil }.map(\.name)
        guard !names.isEmpty else { return }
        let request = Self.request(slot: slot, fireDate: .now.addingTimeInterval(Self.snoozeDelay), kind: "snooze",
                                   title: Self.reminderTitle,
                                   body: Self.body(names: names, child: childName(in: slot), at: slot.scheduled, followUp: false))
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

        // Group every unlogged dose into its slot: one child, one time.
        var unlogged: [Slot: [String]] = [:]
        var children: [String: String] = [:]
        for (key, entry) in entries where !entry.reminders.isEmpty {
            let patient = Self.patientID(of: key)
            if let child = entry.childName { children[patient] = child }
            for offset in 0..<Self.horizonDays {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
                for reminder in entry.reminders {
                    guard let scheduled = calendar.date(bySettingHour: reminder.hour, minute: reminder.minute,
                                                        second: 0, of: day) else { continue }
                    // Already taken or skipped: nothing to remind about.
                    if entry.doses.contains(where: { $0.isScheduled && abs($0.scheduled.timeIntervalSince(scheduled)) < 60 }) { continue }
                    unlogged[Slot(patientID: patient, scheduled: scheduled), default: []]
                        .append(entry.medicineName ?? "your medication")
                }
            }
        }

        for (slot, names) in unlogged {
            let sortedNames = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            let child = children[slot.patientID]
            let followUp = slot.scheduled.addingTimeInterval(Self.followUpDelay)
            for (kind, fireDate) in [("main", slot.scheduled), ("followup", followUp)] where fireDate > now {
                let request = Self.request(
                    slot: slot, fireDate: fireDate, kind: kind, title: Self.reminderTitle,
                    body: Self.body(names: sortedNames, child: child, at: slot.scheduled, followUp: kind == "followup"))
                upcoming.append(request)
                fireDates[request.identifier] = fireDate
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

    private static func identifierPrefix(_ slot: Slot) -> String {
        "\(idPrefix)\(slot.id)|"
    }

    /// "Time for Sam's Hypersal.", or for several: "Time for Sam's 8:00 am
    /// medications: Hypersal and Water for Injection." A follow-up names only
    /// what's still unlogged.
    private static func body(names: [String], child: String?, at scheduled: Date, followUp: Bool) -> String {
        let time = scheduled.formatted(date: .omitted, time: .shortened)
        let list = names.formatted(.list(type: .and))
        if followUp {
            return "Not logged yet from \(time): \(list)."
        }
        let owner = child.map { "\($0)'s" } ?? "your"
        return names.count == 1 ? "Time for \(owner) \(list)." : "Time for \(owner) \(time) medications: \(list)."
    }

    private static func request(slot: Slot, fireDate: Date, kind: String,
                                title: String, body: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = kind == "followup" ? "Follow-up: \(title)" : title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryID
        // Gets through Focus modes, like the Health app's reminders. Needs
        // the Time Sensitive Notifications capability (paid developer team).
        content.interruptionLevel = .timeSensitive
        // One thread per child, so each child's reminders stack together.
        content.threadIdentifier = "med|\(slot.patientID)"
        content.userInfo = ["patientID": slot.patientID, "scheduled": slot.scheduled.timeIntervalSince1970]
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: identifierPrefix(slot) + kind, content: content, trigger: trigger)
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
                    UNNotificationAction(identifier: Action.taken, title: "Mark All as Taken",
                                         icon: UNNotificationActionIcon(systemImageName: "checkmark.circle")),
                    UNNotificationAction(identifier: Action.skipped, title: "Skip All",
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
        // Reminders delivered before grouping carried a medication "key";
        // its patient is the part before the first "|".
        let patientID = (info["patientID"] as? String)
            ?? (info["key"] as? String).map { String($0.prefix { $0 != "|" }) }
        guard let patientID, let stamp = info["scheduled"] as? Double else { return }
        let slot = MedicationStore.Slot(patientID: patientID, scheduled: Date(timeIntervalSince1970: stamp))
        let action = response.actionIdentifier
        await MainActor.run {
            guard let store = NotificationPresenter.shared.store else { return }
            switch action {
            case Action.taken: store.logAll(.taken, in: slot)
            case Action.skipped: store.logAll(.skipped, in: slot)
            case Action.snooze: store.snooze(slot)
            // Tapping the reminder itself opens the logging sheet.
            case UNNotificationDefaultActionIdentifier: store.openSlot = slot
            default: break
            }
        }
    }
}

import CloudKit
import Foundation
import Observation
import UserNotifications

/// The family's own notes, reminder times and dose log for each medication.
/// Never sent to the portal. Kept on this device, and shared with another
/// parent through iCloud when they're invited (see `CareSync`). Keyed by
/// patient and medication, so each child's data stays separate.
///
/// Reminders work like the Health app's: one notification per child per dose
/// time, covering every medication due then ("Time for Sam's 8:00 am
/// medications: …"), with Mark All as Taken / Skip All / Snooze actions, and
/// a follow-up (30 minutes later by default) naming whatever still isn't logged. Tapping a
/// reminder opens a sheet to log each medication. Each slot is its own
/// one-off notification (not a repeating trigger), so a day's follow-up can
/// be dropped once everything in it is logged.
@MainActor
@Observable
final class MedicationStore {
    /// The one store, so widget and Live Activity buttons (which iOS runs in
    /// the app, sometimes without any screen) can reach it.
    static let shared = MedicationStore()

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
    /// Settings > Medication Reminders, in minutes.
    static let snoozeMinutesKey = "snoozeMinutes"
    static let followUpMinutesKey = "followUpMinutes"
    static let snoozeChoices = [5, 10, 15, 30]
    /// 0 turns the follow-up off.
    static let followUpChoices = [0, 15, 30, 60]

    static var snoozeMinutes: Int {
        UserDefaults.standard.object(forKey: snoozeMinutesKey) as? Int ?? 10
    }
    static var followUpMinutes: Int {
        UserDefaults.standard.object(forKey: followUpMinutesKey) as? Int ?? 30
    }
    static var snoozeDelay: TimeInterval { TimeInterval(snoozeMinutes * 60) }
    static let categoryID = "MEDICATION_REMINDER"
    /// iOS keeps at most 64 pending notifications per app; leave headroom.
    private static let maxPending = 60
    private static let horizonDays = 30
    private static let idPrefix = "med|"

    private var entries: [String: Entry] = [:]
    @ObservationIgnored private var rescheduleTask: Task<Void, Never>?

    /// Which shared record each local medication matches, and shared data
    /// for medications this phone hasn't loaded yet.
    private struct SharingState: Codable {
        /// Local key → shared identity.
        var links: [String: SyncRef] = [:]
        /// Keyed by `SyncRef.id`; merged in once the medication is linked.
        var orphans: [String: Entry] = [:]
    }
    private var sharing = SharingState()

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

    @ObservationIgnored private let sharingURL: URL = {
        URL.applicationSupportDirectory.appending(path: "medication-sharing.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = saved
        }
        if let data = try? Data(contentsOf: sharingURL),
           let saved = try? JSONDecoder().decode(SharingState.self, from: data) {
            sharing = saved
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
        let note = MedicationNote(id: UUID(), text: trimmed, date: .now)
        entries[key, default: Entry()].notes.append(note)
        save()
        share(key) { _ in (.note, note.id.uuidString) }
    }

    func deleteNote(_ note: MedicationNote, for key: String) {
        entries[key]?.notes.removeAll { $0.id == note.id }
        save()
        share(key, deleted: true) { _ in (.note, note.id.uuidString) }
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
        share(key) { (.schedule, $0.med) }
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
        share(key, deleted: status == nil) { (.dose, Self.doseName($0, scheduled: scheduled)) }

        clearDeliveredIfLogged(key: key, scheduled: scheduled)
        refreshNotifications()
    }

    /// Once everything in the slot is logged, its reminder, follow-up and
    /// snooze are done with, and can leave Notification Centre, as in the
    /// Health app. (A partly logged slot keeps a follow-up for the rest; the
    /// reschedule rebuilds it with only those names.)
    private func clearDeliveredIfLogged(key: String, scheduled: Date) {
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
        let log = DoseLog(scheduled: date, status: .taken, loggedAt: .now, isAsNeeded: true)
        entries[key, default: Entry()].doses.append(log)
        save()
        share(key) { (.asNeeded, Self.asNeededName($0, log)) }
    }

    /// Undoes an as-needed dose logged by mistake.
    func removeAsNeeded(_ log: DoseLog, for key: String) {
        entries[key]?.doses.removeAll { !$0.isScheduled && $0.loggedAt == log.loggedAt }
        save()
        share(key, deleted: true) { (.asNeeded, Self.asNeededName($0, log)) }
    }

    /// "Remind Me in 10 Minutes" (or as set in Settings): a one-off repeat
    /// for what's still unlogged.
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
            var fires = [("main", slot.scheduled)]
            if Self.followUpMinutes > 0 {
                fires.append(("followup", slot.scheduled.addingTimeInterval(TimeInterval(Self.followUpMinutes * 60))))
            }
            for (kind, fireDate) in fires where fireDate > now {
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


    // MARK: Widgets

    /// Today's scheduled doses for a child, across every medication with
    /// reminders, earliest first.
    func todayDoses(patientID: String) -> [(name: String, time: Date, status: DoseLog.Status?)] {
        entries
            .filter { Self.patientID(of: $0.key) == patientID && !$0.value.reminders.isEmpty }
            .flatMap { key, entry in
                doses(for: key).map { (name: entry.medicineName ?? "Medication", time: $0.scheduled, status: $0.status) }
            }
            .sorted { $0.time < $1.time }
    }

    /// Doses logged from a widget while the app couldn't be reached.
    func applyPendingDoseLogs() {
        let pending = PendingDoseLogs.load()
        guard !pending.entries.isEmpty else { return }
        for entry in pending.entries {
            let slot = Slot(patientID: entry.patientID, scheduled: entry.scheduled)
            logAll(entry.taken ? .taken : .skipped, in: slot)
        }
        PendingDoseLogs().save()
    }

    // MARK: Sharing between parents

    /// Links this phone's medications for a child to their shared identity
    /// (UR number + medicine name). Call once the UR number is known.
    func linkForSharing(patientID: String, urNumber: String, medications: [(id: String, name: String)]) {
        let zone = SyncRef.zoneName(urNumber: urNumber)
        CareSync.shared.noteChild(patientID: patientID, zone: zone)
        var changed = false
        for medication in medications {
            let key = Self.key(patientID: patientID, medicationID: medication.id)
            let ref = SyncRef(zone: zone, med: SyncRef.medKey(name: medication.name))
            if sharing.links[key] != ref {
                sharing.links[key] = ref
                changed = true
                // Newly matched to a shared child: send what this phone has.
                for (kind, name) in recordNames(key: key, ref: ref) {
                    CareSync.shared.changed(kind, name: name, zone: zone)
                }
            }
            if let orphan = sharing.orphans.removeValue(forKey: ref.id) {
                merge(orphan, into: key)
                changed = true
            }
        }
        if changed {
            save()
            saveSharing()
            refreshNotifications()
        }
    }

    /// Everything this phone holds for a child's zone, as record names.
    func recordNames(inZone zone: String) -> [(CareSync.Kind, String)] {
        sharing.links.filter { $0.value.zone == zone }.flatMap { recordNames(key: $0.key, ref: $0.value) }
    }

    private func recordNames(key: String, ref: SyncRef) -> [(CareSync.Kind, String)] {
        guard let entry = entries[key] else { return [] }
        var names: [(CareSync.Kind, String)] = []
        if !entry.reminders.isEmpty { names.append((.schedule, ref.med)) }
        for log in entry.doses {
            names.append(log.isScheduled ? (.dose, Self.doseName(ref, scheduled: log.scheduled))
                                         : (.asNeeded, Self.asNeededName(ref, log)))
        }
        names += entry.notes.map { (.note, $0.id.uuidString) }
        return names
    }

    private static func doseName(_ ref: SyncRef, scheduled: Date) -> String {
        "\(ref.med).\(Int((scheduled.timeIntervalSince1970 / 60).rounded()))"
    }

    private static func asNeededName(_ ref: SyncRef, _ log: DoseLog) -> String {
        "\(ref.med).\(Int(log.loggedAt.timeIntervalSince1970))"
    }

    /// Tells CareSync a record changed, if this medication is shared.
    private func share(_ key: String, deleted: Bool = false, _ name: (SyncRef) -> (CareSync.Kind, String)) {
        guard let ref = sharing.links[key] else { return }
        let (kind, recordName) = name(ref)
        CareSync.shared.changed(kind, name: recordName, zone: ref.zone, deleted: deleted)
    }

    /// Local keys for a shared medication (normally one).
    private func keys(for ref: SyncRef) -> [String] {
        sharing.links.filter { $0.value == ref }.map(\.key)
    }

    private func entry(for ref: SyncRef) -> Entry? {
        keys(for: ref).lazy.compactMap { self.entries[$0] }.first ?? sharing.orphans[ref.id]
    }

    /// Changes a shared medication's data wherever it's held: the linked
    /// local entry, or an orphan until the medication loads on this phone.
    private func mutate(_ ref: SyncRef, _ change: (inout Entry) -> Void) {
        let keys = keys(for: ref)
        if keys.isEmpty {
            change(&sharing.orphans[ref.id, default: Entry()])
        } else {
            for key in keys { change(&entries[key, default: Entry()]) }
        }
    }

    private func merge(_ other: Entry, into key: String) {
        var entry = entries[key] ?? Entry()
        if entry.reminders.isEmpty { entry.reminders = other.reminders }
        entry.medicineName = entry.medicineName ?? other.medicineName
        entry.childName = entry.childName ?? other.childName
        for log in other.doses where !entry.doses.contains(where: { Self.sameDose($0, log) }) {
            entry.doses.append(log)
        }
        for note in other.notes where !entry.notes.contains(where: { $0.id == note.id }) {
            entry.notes.append(note)
        }
        entries[key] = entry
    }

    private static func sameDose(_ a: DoseLog, _ b: DoseLog) -> Bool {
        a.isScheduled == b.isScheduled && (a.isScheduled
            ? abs(a.scheduled.timeIntervalSince(b.scheduled)) < 60
            : Int(a.loggedAt.timeIntervalSince1970) == Int(b.loggedAt.timeIntervalSince1970))
    }

    /// Fills a record from this phone's data. False if the item's gone.
    func fill(_ record: CKRecord, zone: String) -> Bool {
        let parts = record.recordID.recordName.split(separator: ".", maxSplits: 2).map(String.init)
        guard parts.count >= 2, let kind = CareSync.Kind(rawValue: parts[0]) else { return false }
        let fields = record.encryptedValues
        switch kind {
        case .schedule:
            let ref = SyncRef(zone: zone, med: parts[1])
            guard let entry = entry(for: ref),
                  let json = try? JSONEncoder().encode(entry.reminders) else { return false }
            record["med"] = ref.med
            fields["reminders"] = String(decoding: json, as: UTF8.self)
            fields["medicineName"] = entry.medicineName
            fields["childName"] = entry.childName
        case .dose, .asNeeded:
            guard parts.count == 3, let stamp = Int(parts[2]) else { return false }
            let ref = SyncRef(zone: zone, med: parts[1])
            let log = entry(for: ref)?.doses.first { log in
                kind == .dose
                    ? log.isScheduled && Int((log.scheduled.timeIntervalSince1970 / 60).rounded()) == stamp
                    : !log.isScheduled && Int(log.loggedAt.timeIntervalSince1970) == stamp
            }
            guard let log else { return false }
            record["med"] = ref.med
            fields["status"] = log.status.rawValue
            fields["scheduled"] = log.scheduled
            fields["loggedAt"] = log.loggedAt
        case .note:
            guard let id = UUID(uuidString: parts[1]) else { return false }
            let found = sharing.links.filter { $0.value.zone == zone }.lazy.compactMap { key, ref in
                self.entries[key]?.notes.first { $0.id == id }.map { (ref, $0) }
            }.first
            guard let (ref, note) = found else { return false }
            record["med"] = ref.med
            fields["text"] = note.text
            fields["date"] = note.date
        case .question:
            // Visit questions are filled by AppointmentQuestionsStore.
            return false
        }
        return true
    }

    /// Applies a record another parent saved.
    func applyRemote(_ record: CKRecord, zone: String) {
        let parts = record.recordID.recordName.split(separator: ".", maxSplits: 2).map(String.init)
        guard parts.count >= 2, let kind = CareSync.Kind(rawValue: parts[0]),
              let med = record["med"] as? String else { return }
        let ref = SyncRef(zone: zone, med: med)
        let fields = record.encryptedValues
        switch kind {
        case .schedule:
            guard let json = fields["reminders"] as? String,
                  let reminders = try? JSONDecoder().decode([Reminder].self, from: Data(json.utf8)) else { return }
            mutate(ref) { entry in
                entry.reminders = reminders
                entry.medicineName = entry.medicineName ?? fields["medicineName"] as? String
                entry.childName = entry.childName ?? fields["childName"] as? String
            }
        case .dose, .asNeeded:
            guard let raw = fields["status"] as? String, let status = DoseLog.Status(rawValue: raw),
                  let scheduled = fields["scheduled"] as? Date,
                  let loggedAt = fields["loggedAt"] as? Date else { return }
            let log = DoseLog(scheduled: scheduled, status: status, loggedAt: loggedAt,
                              isAsNeeded: kind == .asNeeded ? true : nil)
            mutate(ref) { entry in
                entry.doses.removeAll { Self.sameDose($0, log) }
                entry.doses.append(log)
            }
            if kind == .dose {
                for key in keys(for: ref) { clearDeliveredIfLogged(key: key, scheduled: scheduled) }
            }
        case .note:
            guard let id = UUID(uuidString: parts[1]), let text = fields["text"] as? String,
                  let date = fields["date"] as? Date else { return }
            mutate(ref) { entry in
                entry.notes.removeAll { $0.id == id }
                entry.notes.append(MedicationNote(id: id, text: text, date: date))
            }
        case .question:
            return
        }
        save()
        saveSharing()
        refreshNotifications()
    }

    /// Applies another parent's deletion (an undone dose or a deleted note).
    func applyRemoteDeletion(recordName: String, zone: String) {
        let parts = recordName.split(separator: ".", maxSplits: 2).map(String.init)
        guard parts.count >= 2, let kind = CareSync.Kind(rawValue: parts[0]) else { return }
        switch kind {
        case .schedule, .question:
            return
        case .dose, .asNeeded:
            guard parts.count == 3, let stamp = Int(parts[2]) else { return }
            mutate(SyncRef(zone: zone, med: parts[1])) { entry in
                entry.doses.removeAll { log in
                    kind == .dose
                        ? log.isScheduled && Int((log.scheduled.timeIntervalSince1970 / 60).rounded()) == stamp
                        : !log.isScheduled && Int(log.loggedAt.timeIntervalSince1970) == stamp
                }
            }
        case .note:
            guard let id = UUID(uuidString: parts[1]) else { return }
            for key in sharing.links.filter({ $0.value.zone == zone }).map(\.key) {
                entries[key]?.notes.removeAll { $0.id == id }
            }
            for ref in sharing.orphans.keys where ref.hasPrefix(zone + "|") {
                sharing.orphans[ref]?.notes.removeAll { $0.id == id }
            }
        }
        save()
        saveSharing()
        refreshNotifications()
    }

    private func saveSharing() {
        guard let data = try? JSONEncoder().encode(sharing) else { return }
        try? data.write(to: sharingURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        WidgetPublisher.shared.dosesChanged()
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
        UNUserNotificationCenter.current().delegate = self
        registerCategories()
    }

    /// The buttons, again when the snooze length changes in Settings.
    func registerCategories() {
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(
                identifier: MedicationStore.categoryID,
                actions: [
                    UNNotificationAction(identifier: Action.taken, title: "Mark All as Taken",
                                         icon: UNNotificationActionIcon(systemImageName: "checkmark.circle")),
                    UNNotificationAction(identifier: Action.skipped, title: "Skip All",
                                         icon: UNNotificationActionIcon(systemImageName: "xmark.circle")),
                    UNNotificationAction(identifier: Action.snooze, title: "Remind Me in \(MedicationStore.snoozeMinutes) Minutes",
                                         icon: UNNotificationActionIcon(systemImageName: "clock"))
                ],
                intentIdentifiers: [])
        ])
    }

    // Completion-handler versions, not the async ones: iOS calls these on
    // the main thread and requires the completion handler there too. The
    // async bridges can finish on another thread, which crashed the app when
    // a reminder was tapped.

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        // Reminders delivered before grouping carried a medication "key";
        // its patient is the part before the first "|".
        let patientID = (info["patientID"] as? String)
            ?? (info["key"] as? String).map { String($0.prefix { $0 != "|" }) }
        guard let patientID, let stamp = info["scheduled"] as? Double else {
            completionHandler()
            return
        }
        let slot = MedicationStore.Slot(patientID: patientID, scheduled: Date(timeIntervalSince1970: stamp))
        let action = response.actionIdentifier
        // Called once, on the main thread, as iOS requires.
        nonisolated(unsafe) let completionHandler = completionHandler
        let handle: @Sendable () -> Void = {
            MainActor.assumeIsolated {
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
            completionHandler()
        }
        // Normally already on the main thread; hop there if not.
        if Thread.isMainThread { handle() } else { DispatchQueue.main.async(execute: handle) }
    }
}

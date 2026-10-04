import AppIntents
import SwiftUI

// Pages under Settings > App.

/// Medication reminder timing, Discover alerts, and a way to the iOS
/// notification settings.
struct NotificationSettingsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(MedicationStore.self) private var medicationStore
    @AppStorage(MedicationStore.snoozeMinutesKey) private var snoozeMinutes = 10
    @AppStorage(MedicationStore.followUpMinutesKey) private var followUpMinutes = 30
    @AppStorage(DiscoverAlerts.newsKey) private var alertsForNews = false
    @AppStorage(DiscoverAlerts.factSheetsKey) private var alertsForFactSheets = false

    var body: some View {
        List {
            Section {
                Picker(selection: $snoozeMinutes) {
                    ForEach(MedicationStore.snoozeChoices, id: \.self) { Text("\($0) minutes").tag($0) }
                } label: {
                    SettingsRow("Snooze", symbol: "clock.fill", color: Theme.medication)
                }
                Picker(selection: $followUpMinutes) {
                    ForEach(MedicationStore.followUpChoices, id: \.self) { minutes in
                        Text(minutes == 0 ? "Off" : "After \(minutes) minutes").tag(minutes)
                    }
                } label: {
                    SettingsRow("Follow-up Reminder", symbol: "bell.and.waves.left.and.right.fill", color: Theme.medication)
                }
            } header: {
                Text("Medication Reminders")
            } footer: {
                Text("Snooze is how long Remind Me waits. A follow-up names any medication still not logged after its reminder.")
            }
            .onChange(of: snoozeMinutes) { NotificationPresenter.shared.registerCategories() }
            .onChange(of: followUpMinutes) { medicationStore.refreshNotifications() }

            Section {
                Toggle(isOn: $alertsForNews) {
                    SettingsRow("New RCH News", symbol: "newspaper.fill", color: Theme.brand)
                }
                Toggle(isOn: $alertsForFactSheets) {
                    SettingsRow("New Fact Sheets", symbol: "doc.text.fill", color: Theme.green)
                }
            } header: {
                Text("Discover Alerts")
            } footer: {
                Text("A notification when RCH News posts a story, or Kids or Teen Health Info adds a fact sheet. iOS checks every few hours, when Background App Refresh is on for myRCH.")
            }
            .onChange(of: alertsForNews) { _, isOn in discoverAlertsChanged(turnedOn: isOn) }
            .onChange(of: alertsForFactSheets) { _, isOn in discoverAlertsChanged(turnedOn: isOn) }

            Section {
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                } label: {
                    SettingsRow("iOS Notification Settings", symbol: "gear", color: .gray, showsChevron: true)
                }
                .foregroundStyle(.primary)
            } footer: {
                Text("Turn myRCH's notifications on or off, or change how they appear, in the Settings app.")
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Asks for notification permission when an alert's turned on, and
    /// schedules (or cancels) the background check.
    private func discoverAlertsChanged(turnedOn: Bool) {
        DiscoverAlerts.schedule()
        guard turnedOn else { return }
        Task {
            // Gives the next check something to compare with.
            await RCHContentStore.shared.refresh(minimumInterval: 0)
            _ = await DiscoverAlerts.requestPermission()
        }
    }
}

/// Live Activities and what widgets may show while the iPhone is locked.
struct LockScreenSettingsView: View {
    @AppStorage(ActivityManager.enabledKey) private var liveActivitiesEnabled = true
    /// The Allergy Alert widget shows allergies without unlocking, so it's opt-in.
    @AppStorage(WidgetPublisher.showsAllergiesKey) private var showsAllergiesOnLockScreen = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: $liveActivitiesEnabled) {
                    SettingsRow("Live Activities", symbol: "platter.filled.bottom.iphone", color: Theme.medication)
                }
                .onChange(of: liveActivitiesEnabled) { WidgetPublisher.shared.settingsChanged() }
            } footer: {
                Text("Shows a dose that's due, with Taken and Skip, and the day of a visit, on the Lock Screen and in the Dynamic Island. They start when you open myRCH.")
            }
            Section {
                Toggle(isOn: $showsAllergiesOnLockScreen) {
                    SettingsRow("Allergies on Lock Screen", symbol: "allergens.fill", color: .orange)
                }
                .onChange(of: showsAllergiesOnLockScreen) { WidgetPublisher.shared.settingsChanged() }
            } header: {
                Text("Widgets")
            } footer: {
                Text("Lets the Allergy Alert widget show allergies without unlocking your iPhone, like Medical ID, so a first responder can see them. Anyone who picks up your phone can too.")
            }
        }
        .navigationTitle("Lock Screen & Widgets")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The app's shortcuts, with the phrase for logging a dose.
struct SiriSettingsView: View {
    var body: some View {
        List {
            Section {
                ShortcutsLink()
                    .shortcutsLinkStyle(.automaticOutline)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } footer: {
                Text("Say \u{201C}Hey Siri, log next dose in myRCH\u{201D} to mark the next medication due today as taken.")
            }
        }
        .navigationTitle("Siri & Shortcuts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

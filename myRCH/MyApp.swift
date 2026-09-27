import SwiftUI

@main struct MyApp: App {
    @State private var session = Session()
    @State private var medicationStore: MedicationStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = MedicationStore()
        _medicationStore = State(initialValue: store)
        // Before launch finishes, so a tapped reminder action is handled.
        NotificationPresenter.shared.register(store: store)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // The RCH blue-teal everywhere, including sign-in and sheets.
                // (The AccentColor asset matches, for alerts and system UI.)
                .tint(Theme.brand)
                .environment(session)
                .environment(medicationStore)
                .task { await session.restoreSession() }
        }
        // Reminders are scheduled a window ahead; top it up on each return.
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { medicationStore.refreshNotifications() }
        }
    }
}

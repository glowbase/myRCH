import CloudKit
import SwiftUI
import UIKit

@main struct MyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = Session()
    @State private var medicationStore: MedicationStore
    @State private var careSync = CareSync.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue

    init() {
        let store = MedicationStore.shared
        _medicationStore = State(initialValue: store)
        // Before launch finishes, so a tapped reminder action is handled.
        NotificationPresenter.shared.register(store: store)
        CareSync.shared.store = store
        WatchBridge.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // The RCH blue-teal everywhere, including sign-in and sheets.
                // (The AccentColor asset matches, for alerts and system UI.)
                .tint(Theme.brand)
                .environment(session)
                .environment(medicationStore)
                .environment(careSync)
                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
                .task { await session.restoreSession() }
                .task { await careSync.start() }
        }
        // Reminders are scheduled a window ahead; top it up on each return,
        // and pick up anything another parent changed while away.
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                medicationStore.applyPendingDoseLogs()
                medicationStore.refreshNotifications()
                // Live Activities can only start while the app is open.
                WidgetPublisher.shared.dosesChanged()
                Task { await careSync.syncNow() }
            }
        }
    }
}

/// Registers for the silent pushes CloudKit sends when a shared child's
/// reminders change, and routes accepted iCloud share invitations.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

/// Accepts a "Share Reminders" invitation, whether the app was running or
/// launched by tapping the link.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            Task { await CareSync.shared.accept(metadata) }
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { await CareSync.shared.accept(metadata) }
    }
}

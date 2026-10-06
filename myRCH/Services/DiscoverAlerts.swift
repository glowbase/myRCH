import BackgroundTasks
import Foundation
import UserNotifications

/// Notifications for new RCH News posts and new Kids and Teen Health Info
/// fact sheets. Neither site sends pushes, so the app checks in the
/// background with Background App Refresh, which iOS runs every few hours
/// at times it picks around how the app's used, and compares with
/// Discover's saved copy. Off until turned on in Settings.
enum DiscoverAlerts {
    static let taskID = "com.glowbase.myRCH.discover-refresh"
    static let newsKey = "discoverAlertsNews"
    static let factSheetsKey = "discoverAlertsFactSheets"

    static var wantsNews: Bool { UserDefaults.standard.bool(forKey: newsKey) }
    static var wantsFactSheets: Bool { UserDefaults.standard.bool(forKey: factSheetsKey) }

    /// Asks iOS for the next background check, when any alert is on.
    /// iOS decides when it runs; this is the earliest.
    static func schedule() {
        guard wantsNews || wantsFactSheets else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = .now.addingTimeInterval(4 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// The background check: refreshes Discover's saved copy (which also
    /// keeps it current for offline reading) and notifies about anything
    /// new. Fact sheet pages aren't downloaded here; there isn't time.
    static func checkInBackground() async {
        schedule()
        guard wantsNews || wantsFactSheets else { return }
        let updates = await RCHContentStore.shared.refresh(minimumInterval: 0, downloadsSheets: false)
        await notify(updates)
    }

    /// Asks for permission the first time an alert is turned on.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    // MARK: Notifications

    /// A post or sheet a notification opens when tapped. Nonisolated: read
    /// by the notification delegate, off the main actor.
    nonisolated static let postKey = "discoverPost"
    nonisolated static let sheetKey = "discoverSheet"

    private static func notify(_ updates: RCHContentStore.Updates) async {
        let center = UNUserNotificationCenter.current()
        if wantsNews {
            // One each for the newest few; more than that would be a flood.
            for post in updates.posts.sorted(by: { $0.date > $1.date }).prefix(3) {
                let content = UNMutableNotificationContent()
                content.title = "New on RCH News"
                content.body = post.title
                content.threadIdentifier = "discover-news"
                content.userInfo = [postKey: post.id]
                try? await center.add(UNNotificationRequest(identifier: "discover-post-\(post.id)",
                                                            content: content, trigger: nil))
            }
        }
        if wantsFactSheets {
            for library in FactSheet.Library.allCases {
                let sheets = updates.sheets.filter { $0.library == library }
                guard let first = sheets.first else { continue }
                let content = UNMutableNotificationContent()
                content.threadIdentifier = "discover-\(library.rawValue)"
                if sheets.count == 1 {
                    content.title = "New \(library.title) fact sheet"
                    content.body = first.title
                    content.userInfo = [sheetKey: first.url.absoluteString]
                } else {
                    // Several at once (often a site update): one summary,
                    // which opens the first.
                    content.title = "\(sheets.count) new \(library.title) fact sheets"
                    let titles = sheets.prefix(3).map(\.title)
                    content.body = sheets.count > 3
                        ? titles.joined(separator: ", ") + " and more"
                        : titles.formatted(.list(type: .and))
                    content.userInfo = [sheetKey: first.url.absoluteString]
                }
                try? await center.add(UNNotificationRequest(identifier: "discover-sheets-\(library.rawValue)-\(Date.now.timeIntervalSince1970)",
                                                            content: content, trigger: nil))
            }
        }
    }
}

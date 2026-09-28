import Foundation

/// Starts, updates and ends the app's Live Activities from the widget
/// snapshot. (Filled in by the Live Activities feature.)
@MainActor
final class ActivityManager {
    static let shared = ActivityManager()
    private init() {}

    func refresh(_ snapshot: WidgetSnapshot) {}
    func endAll() {}
}

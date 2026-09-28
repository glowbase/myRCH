import SwiftUI

@main
struct myRCHWatchApp: App {
    @State private var store = WatchStore.shared

    init() {
        WatchStore.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}

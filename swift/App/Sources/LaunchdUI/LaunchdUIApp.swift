import LaunchdCore
import SwiftUI

@main
struct LaunchdUIApp: App {
    var body: some Scene {
        Window("launchd-ui", id: "main") {
            ContentView()
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

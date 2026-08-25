import LaunchdCore
import SwiftUI

@main
struct LaunchdUIApp: App {
    var body: some Scene {
        Window("Launchd UI", id: "main") {
            ContentView()
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

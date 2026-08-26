import AppKit
import LaunchdCore
import SwiftUI

@main
struct LaunchdUIApp: App {
    // The detail windows are separate scenes, so the job list can no longer be owned by
    // ContentView: saving an edit from a detail window has to refresh the main list.
    @State private var model = JobsModel()

    var body: some Scene {
        Window("Launchd UI", id: "main") {
            ContentView()
                .environment(model)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            // SwiftUI's stock Edit menu has no Find item, so NSTextView's find bar is
            // unreachable without one -- setting usesFindBar alone does nothing.
            CommandGroup(after: .textEditing) {
                Divider()
                Button("Find…") { TextFinderCommand.show() }
                    .keyboardShortcut("f")
                Button("Find Next") { TextFinderCommand.next() }
                    .keyboardShortcut("g")
                Button("Find Previous") { TextFinderCommand.previous() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }

        // Keyed by plist path, so asking for the same job twice raises the window that is
        // already open instead of stacking duplicates -- the Get Info behaviour.
        WindowGroup(id: DetailWindow.id, for: String.self) { $plistPath in
            if let plistPath {
                JobDetailView(plistPath: plistPath)
                    .environment(model)
            }
        }
        // A request, not a guarantee: macOS opens these narrower than this, which is
        // why only the tab strip is asked to fit in the toolbar.
        .defaultSize(width: 880, height: 620)
        .windowToolbarStyle(.unified)
    }
}

enum DetailWindow {
    static let id = "job-detail"
}

/// performTextFinderAction(_:) picks its action off the sender's `tag`, so the command
/// needs a tagged sender rather than a plain SwiftUI Button. Sending to a nil target
/// walks the responder chain, so this reaches whichever text view has focus and is a
/// no-op when none does.
enum TextFinderCommand {
    static func show() { send(.showFindInterface) }
    static func next() { send(.nextMatch) }
    static func previous() { send(.previousMatch) }

    private static func send(_ action: NSTextFinder.Action) {
        NSApp.sendAction(
            #selector(NSTextView.performTextFinderAction(_:)),
            to: nil,
            from: TaggedSender(tag: action.rawValue))
    }

    private final class TaggedSender: NSObject {
        @objc let tag: Int
        init(tag: Int) {
            self.tag = tag
            super.init()
        }
    }
}

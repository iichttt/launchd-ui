import AppKit
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
    }
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

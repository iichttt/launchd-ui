import AppKit
import SwiftUI

/// AppKit's search field, wrapped so the toolbar gets the real control -- rounded
/// search styling, the magnifier glyph, and the clear button -- rather than a
/// TextField dressed up to look like one.
struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    var onCancel: () -> Void
    var onEndEditing: () -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        field.placeholderString = "Search agents"
        // Take focus once the field is in a window, so clicking the magnifier drops
        // the caret straight into the field.
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NativeSearchField

        init(_ parent: NativeSearchField) { self.parent = parent }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ note: Notification) {
            parent.onEndEditing()
        }

        func control(
            _ control: NSControl, textView: NSTextView, doCommandBy selector: Selector
        ) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}

/// A magnifier button that expands into the search field, and folds back once the
/// field is empty and no longer being edited.
struct ExpandingSearchField: View {
    @Binding var text: String
    @State private var expanded = false

    var body: some View {
        Group {
            if expanded {
                NativeSearchField(
                    text: $text,
                    onCancel: collapse,
                    onEndEditing: { if text.isEmpty { collapse() } }
                )
                .frame(width: 200)
            } else {
                Button { expanded = true } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Search agents")
                .accessibilityLabel("Search agents")
            }
        }
        // A non-empty filter must stay visible, otherwise the list looks wrong with no
        // way to see why.
        .onChange(of: text) { _, new in if !new.isEmpty { expanded = true } }
    }

    private func collapse() {
        text = ""
        expanded = false
    }
}

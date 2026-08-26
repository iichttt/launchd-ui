import AppKit
import LaunchdCore
import SwiftUI

struct LogViewerView: View {
    var logPath: String
    var tailLines: Int = 200

    @State private var content = ""
    @State private var modifiedAt: Date?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(logPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let modifiedAt {
                    Text("(\(shortTimestamp(modifiedAt)))")
                        .font(.caption).foregroundStyle(.secondary).fixedSize()
                }
                Spacer(minLength: 8)
                Button {
                    Task { await load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(loading)

                Button {
                    Task {
                        do { try JobService.clearLogFile(path: logPath) }
                        catch { self.error = error.localizedDescription; return }
                        await load()
                    }
                } label: {
                    Label("Clear", systemImage: "trash")
                }

                Button {
                    do { try JobService.openLogInEditor(path: logPath) }
                    catch { self.error = error.localizedDescription }
                } label: {
                    Label("Open in Editor", systemImage: "square.and.pencil")
                }
            }
            // Borderless caption text read as a label rather than a control; a bordered
            // small button is the standard affordance for an inline action row.
            .buttonStyle(.bordered)
            .controlSize(.small)

            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            } else {
                // The log owns its pane now instead of sharing a scrolling column with
                // a second one, so it takes whatever height the window offers.
                LogTextView(text: content.isEmpty ? "(empty)" : content)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await load() }
    }

    /// Reads the log off the main actor: the whole file is pulled into memory to take
    /// its tail, which stalls the UI on a log that an agent has let grow.
    private func load() async {
        loading = true
        error = nil
        let path = logPath
        let lines = tailLines
        do {
            let result = try await Task.detached {
                try JobService.readLogFile(path: path, tailLines: lines)
            }.value
            content = result.content
            modifiedAt = result.modifiedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        } catch {
            self.error = error.localizedDescription
            content = ""
        }
        loading = false
    }

    /// Matches LogViewer.tsx's "M/D HH:MM:SS" stamp.
    private func shortTimestamp(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%d/%d %02d:%02d:%02d",
            c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
}

/// AppKit's text view, so the log gets the real control: a find bar on Cmd-F, native
/// selection, and line-based layout instead of the whole file laid out as one `Text`.
/// Its own bezel replaces the rounded rectangle that used to imitate one.
struct LogTextView: NSViewRepresentable {
    var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.isRichText = false
        textView.isSelectable = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.font = .monospacedSystemFont(
            ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.backgroundColor = .textBackgroundColor
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Re-setting the string drops selection and scroll position, so only do it when
        // the log actually changed.
        guard textView.string != text else { return }
        textView.string = text
        // A log reads newest-last, so open at the end rather than the top.
        textView.scrollToEndOfDocument(nil)
    }
}

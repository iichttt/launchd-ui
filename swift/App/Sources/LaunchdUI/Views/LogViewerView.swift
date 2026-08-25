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
                Button("Refresh") { Task { await load() } }.disabled(loading)
                Button("Clear") {
                    Task {
                        do { try JobService.clearLogFile(path: logPath) }
                        catch { self.error = error.localizedDescription; return }
                        await load()
                    }
                }
                Button("Open in Editor") {
                    do { try JobService.openLogInEditor(path: logPath) }
                    catch { self.error = error.localizedDescription }
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)

            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            } else {
                ScrollView {
                    Text(content.isEmpty ? "(empty)" : content)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 220)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.3)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
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

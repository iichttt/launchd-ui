import LaunchdCore
import SwiftUI

struct JobListView: View {
    var jobs: [JobListEntry]
    var loading: Bool
    var onStart: (JobListEntry) -> Void
    var onStop: (JobListEntry) -> Void
    var onRestart: (JobListEntry) -> Void
    var onKickstart: (JobListEntry) -> Void
    var onDelete: (JobListEntry) -> Void
    var onSelect: (JobListEntry) -> Void
    var onReveal: (JobListEntry) -> Void

    var body: some View {
        if loading {
            centeredMessage("Loading agents...")
        } else if jobs.isEmpty {
            centeredMessage("No agents found")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    JobListHeader()
                    ForEach(jobs) { job in
                        JobRowView(
                            job: job,
                            onStart: onStart,
                            onStop: onStop,
                            onRestart: onRestart,
                            onKickstart: onKickstart,
                            onDelete: onDelete,
                            onSelect: onSelect,
                            onReveal: onReveal
                        )
                        Divider()
                    }
                }
            }
        }
    }

    private func centeredMessage(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Column widths are shared between the header and every row so the list lines up
/// without a real Table (which cannot host per-row action buttons cleanly).
enum JobColumn {
    static let source: CGFloat = 70
    static let status: CGFloat = 80
    static let pid: CGFloat = 60
    static let lastRun: CGFloat = 80
    static let actions: CGFloat = 150
}

struct JobListHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("Label").frame(maxWidth: .infinity, alignment: .leading)
            Text("Source").frame(width: JobColumn.source, alignment: .leading)
            Text("Status").frame(width: JobColumn.status, alignment: .leading)
            Text("PID").frame(width: JobColumn.pid, alignment: .trailing)
            Text("Last Run").frame(width: JobColumn.lastRun, alignment: .trailing)
            Text("Actions").frame(width: JobColumn.actions, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.3))
    }
}

struct JobRowView: View {
    var job: JobListEntry
    var onStart: (JobListEntry) -> Void
    var onStop: (JobListEntry) -> Void
    var onRestart: (JobListEntry) -> Void
    var onKickstart: (JobListEntry) -> Void
    var onDelete: (JobListEntry) -> Void
    var onSelect: (JobListEntry) -> Void
    var onReveal: (JobListEntry) -> Void

    @State private var hovering = false

    /// launchd job control is rejected for anything outside ~/Library/LaunchAgents, so the
    /// controls are disabled rather than allowed to fail.
    private var isUserAgent: Bool { job.source == .userAgent }

    var body: some View {
        HStack(spacing: 8) {
            Text(job.label)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            SourceBadge(source: job.source)
                .frame(width: JobColumn.source, alignment: .leading)

            StatusBadge(status: job.status)
                .frame(width: JobColumn.status, alignment: .leading)

            Text(job.pid.map(String.init) ?? "—")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: JobColumn.pid, alignment: .trailing)

            Text(job.lastRunAt.map(formatRelativeTime) ?? "—")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: JobColumn.lastRun, alignment: .trailing)

            actions.frame(width: JobColumn.actions, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(hovering ? Color.secondary.opacity(0.08) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { onSelect(job) }
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 2) {
            if job.status == .running || job.status == .loaded {
                iconButton("stop.fill", help: isUserAgent
                    ? (job.status == .running ? "Stop" : "Unload")
                    : "Cannot stop system agents") { onStop(job) }
            } else {
                iconButton("play.fill", help: isUserAgent ? "Load" : "Cannot load system agents") {
                    onStart(job)
                }
            }

            if job.status != .unloaded {
                iconButton("arrow.clockwise", help: isUserAgent ? "Restart" : "Cannot restart system agents") {
                    onRestart(job)
                }
                iconButton("bolt.fill", help: isUserAgent ? "Run now" : "Cannot run system agents") {
                    onKickstart(job)
                }
            }

            Menu {
                Button("Test Run") { onKickstart(job) }
                    .disabled(!isUserAgent)
                Button("Details") { onSelect(job) }
                Button("Reveal in Finder") { onReveal(job) }
                if isUserAgent {
                    Divider()
                    Button("Delete", role: .destructive) { onDelete(job) }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24)
        }
    }

    private func iconButton(
        _ systemName: String, help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .disabled(!isUserAgent)
        .help(help)
    }
}

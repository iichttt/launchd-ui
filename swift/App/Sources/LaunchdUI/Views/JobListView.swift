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

    @State private var selection = Set<JobListEntry.ID>()
    @State private var sortOrder = [KeyPathComparator(\JobListEntry.label)]

    private var sorted: [JobListEntry] { jobs.sorted(using: sortOrder) }

    var body: some View {
        if loading {
            centeredMessage("Loading agents...")
        } else if jobs.isEmpty {
            centeredMessage("No agents found")
        } else {
            Table(sorted, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Label", value: \.label) { job in
                    Text(job.label)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(job.plistPath)
                }

                TableColumn("Source", value: \.sortableSource) { job in
                    SourceBadge(source: job.source)
                }
                .width(JobColumn.source)

                TableColumn("Status", value: \.sortableStatus) { job in
                    StatusBadge(status: job.status)
                }
                .width(JobColumn.status)

                TableColumn("PID", value: \.sortablePID) { job in
                    Text(job.pid.map(String.init) ?? "—")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(JobColumn.pid)

                TableColumn("Last Run", value: \.sortableLastRun) { job in
                    Text(job.lastRunAt.map(formatRelativeTime) ?? "—")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(JobColumn.lastRun)

                TableColumn("Actions") { job in
                    JobRowActions(
                        job: job,
                        onStart: onStart,
                        onStop: onStop,
                        onRestart: onRestart,
                        onKickstart: onKickstart,
                        onDelete: onDelete,
                        onSelect: onSelect,
                        onReveal: onReveal
                    )
                }
                .width(JobColumn.actions)
            }
            // primaryAction is the Table's double-click handler; the same items back
            // the right-click menu, so both routes reach every action.
            .contextMenu(forSelectionType: JobListEntry.ID.self) { ids in
                if let job = job(for: ids) {
                    Button("Details") { onSelect(job) }
                    Button("Run Now") { onKickstart(job) }
                        .disabled(job.source != .userAgent)
                    Button("Reveal in Finder") { onReveal(job) }
                    if job.source == .userAgent {
                        Divider()
                        Button("Delete", role: .destructive) { onDelete(job) }
                    }
                }
            } primaryAction: { ids in
                if let job = job(for: ids) { onSelect(job) }
            }
        }
    }

    private func job(for ids: Set<JobListEntry.ID>) -> JobListEntry? {
        guard let id = ids.first else { return nil }
        return jobs.first { $0.id == id }
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

/// Table sorting needs a Comparable key path per column, which the badge-backed
/// enums and the optional numeric fields do not provide directly.
extension JobListEntry {
    var sortableSource: String { source.rawValue }
    var sortableStatus: String { status.rawValue }
    /// Unset sorts below every real pid rather than above it.
    var sortablePID: Int { pid ?? -1 }
    var sortableLastRun: Double { lastRunAt ?? 0 }
}

enum JobColumn {
    static let source: CGFloat = 70
    static let status: CGFloat = 80
    static let pid: CGFloat = 60
    static let lastRun: CGFloat = 80
    static let actions: CGFloat = 150
}

struct JobRowActions: View {
    var job: JobListEntry
    var onStart: (JobListEntry) -> Void
    var onStop: (JobListEntry) -> Void
    var onRestart: (JobListEntry) -> Void
    var onKickstart: (JobListEntry) -> Void
    var onDelete: (JobListEntry) -> Void
    var onSelect: (JobListEntry) -> Void
    var onReveal: (JobListEntry) -> Void

    /// launchd job control is rejected for anything outside ~/Library/LaunchAgents, so the
    /// controls are disabled rather than allowed to fail.
    private var isUserAgent: Bool { job.source == .userAgent }

    var body: some View {
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
                Button("Run Now") { onKickstart(job) }
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

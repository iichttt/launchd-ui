import LaunchdCore
import SwiftUI

struct JobDetailView: View {
    var plistPath: String

    @Environment(JobsModel.self) private var model
    @State private var job: LaunchdJob?
    @State private var loadError: String?
    @State private var tab = DetailTab.configuration
    @State private var editing: LaunchdJob?

    /// A log tab carries its path so the selection survives the strip being rebuilt.
    enum DetailTab: Hashable {
        case configuration
        case log(String)
        case flags
        case commands
    }

    var body: some View {
        Group {
            if let job {
                content(for: job)
            } else if let loadError {
                ContentUnavailableView(
                    "Could not load agent",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // The floor is what the toolbar needs: below roughly this width the five-tab
        // strip and the job's label stop fitting and macOS folds the whole toolbar
        // into an overflow menu. `.defaultSize` and an ideal width are both ignored
        // for this scene, but the content's minimum is honoured, so it sets the
        // opening width too.
        .frame(minWidth: 860, minHeight: 460)
        .navigationTitle(job?.label ?? "Loading…")
        .toolbar { toolbarContent }
        .task { await load() }
        // Presented from this window, so dismissing the form returns here rather than
        // dropping the user back to the job list.
        .sheet(item: $editing) { target in
            JobFormView(editingJob: target) { config, path in
                if let path {
                    try JobService.saveJob(plistPath: path, config: config)
                } else {
                    _ = try JobService.createJob(label: config.label, config: config)
                }
                Task {
                    await model.refresh()
                    await load()
                }
            }
        }
    }

    @ViewBuilder
    private func content(for job: LaunchdJob) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            summary(for: job)
            Divider()

            switch tab {
            case .configuration:
                scrolling { ConfigurationTab(job: job) }
            case .flags:
                // Brings its own Form, which scrolls itself.
                FlagsTab(job: job)
            case .commands:
                scrolling { CommandPanelView(job: job) }
            case .log(let path):
                // The log view scrolls itself; nesting it in another scroll view would
                // give the pane two scrollers and no way to reach the bottom.
                LogViewerView(logPath: path)
                    .padding(12)
            }
        }
    }

    private func scrolling(@ViewBuilder _ content: () -> some View) -> some View {
        ScrollView {
            content()
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The window title already carries the label, so this row is only the live state.
    private func summary(for job: LaunchdJob) -> some View {
        HStack(spacing: 10) {
            StatusBadge(status: job.status)
            if let pid = job.pid {
                // verbatim: a plain interpolation would group the digits into "4,211".
                Text(verbatim: "PID \(pid)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if let exit = job.lastExitCode {
                Text(verbatim: "Exit \(exit)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if let lastRun = job.lastRunAt {
                let stamp = Date(timeIntervalSince1970: lastRun / 1000)
                    .formatted(date: .abbreviated, time: .shortened)
                Text("Last run \(stamp)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            // Riding the status row rather than a row of their own, and out of the
            // toolbar: the tab strip plus these two plus a long label overflow the
            // toolbar at the width the window opens at.
            if job.source == .userAgent {
                Button { editing = job } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .help("Edit this agent")
            }
            Button {
                try? JobService.revealInFinder(path: job.plistPath)
            } label: {
                Label("Reveal", systemImage: "folder")
            }
            .help("Reveal the plist in Finder")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Tabs and the two actions live in the window's own toolbar, so neither costs a
    /// row of the pane.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let job {
            // .primaryAction rides the trailing edge; .principal would centre it.
            ToolbarItem(placement: .primaryAction) {
                Picker("View", selection: $tab) {
                    Text("Configuration").tag(DetailTab.configuration)
                    ForEach(job.plist.logStreams) { log in
                        Text(log.title).tag(DetailTab.log(log.path))
                    }
                    Text("Flags").tag(DetailTab.flags)
                    Text("Commands").tag(DetailTab.commands)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    private func load() async {
        let path = plistPath
        do {
            // jobDetail spawns `launchctl list`, so it must not run on the main actor.
            let loaded = try await Task.detached {
                try JobService.jobDetail(plistPath: path)
            }.value
            job = loaded
            // An edit can retarget or drop a log file, which would leave the selection
            // pointing at a tab that no longer exists.
            if case .log(let selected) = tab,
               !loaded.plist.logStreams.contains(where: { $0.path == selected }) {
                tab = .configuration
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct DetailRow: View {
    var label: String
    var value: String?

    var body: some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .leading)
                Text(value)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)
        }
    }
}

private struct ConfigurationTab: View {
    var job: LaunchdJob

    var body: some View {
        let plist = job.plist
        VStack(alignment: .leading, spacing: 2) {
            DetailRow(label: "Label", value: plist.label)
            DetailRow(label: "Program", value: plist.program)

            if let args = plist.programArguments, !args.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Text("Arguments")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(width: 130, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(args.enumerated()), id: \.offset) { index, arg in
                            HStack(alignment: .top, spacing: 4) {
                                Text("[\(index)]").foregroundStyle(.secondary)
                                Text(arg).textSelection(.enabled)
                            }
                            .font(.system(.callout, design: .monospaced))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 2)
            }

            if plist.runAtLoad == true { DetailRow(label: "Run at Load", value: "true") }
            if plist.keepAlive == true { DetailRow(label: "Keep Alive", value: "true") }
            DetailRow(label: "Interval", value: plist.startInterval.map { "\($0)s" })
            DetailRow(label: "Working Dir", value: plist.workingDirectory)
            DetailRow(label: "Stdout", value: plist.standardOutPath)
            DetailRow(label: "Stderr", value: plist.standardErrorPath)
            if plist.wakeSystem == true { DetailRow(label: "Wake System", value: "true") }
            if plist.disabled == true { DetailRow(label: "Disabled", value: "true") }

            if let env = plist.environmentVariables, !env.isEmpty {
                Divider().padding(.vertical, 6)
                Text("Environment Variables").font(.callout.weight(.medium))
                ForEach(env.keys.sorted(), id: \.self) { key in
                    DetailRow(label: key, value: env[key])
                }
            }

            if let intervals = plist.startCalendarInterval, !intervals.isEmpty {
                Divider().padding(.vertical, 6)
                Text("Schedule").font(.callout.weight(.medium))
                Text(CalendarUtils.format(intervals)).font(.callout)
                let upcoming = CalendarUtils.nextOccurrences(multi: intervals, count: 5)
                if !upcoming.isEmpty {
                    Text("Next runs").font(.caption.weight(.medium))
                        .foregroundStyle(.secondary).padding(.top, 4)
                    ForEach(upcoming, id: \.self) { date in
                        Text(CalendarUtils.formatDateTime(date))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct CommandPanelView: View {
    var job: LaunchdJob
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(CommandBuilder.commands(for: job)) { row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(row.label)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(row.destructive ? .red : .secondary)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(row.command, forType: .string)
                            copied = row.command
                        } label: {
                            Label(
                                copied == row.command ? "Copied" : "Copy",
                                systemImage: copied == row.command ? "checkmark" : "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                    Text(row.command)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary.opacity(0.4)))
                }
                .padding(.bottom, 4)
            }
        }
    }
}

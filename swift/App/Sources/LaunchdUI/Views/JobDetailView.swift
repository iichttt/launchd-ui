import LaunchdCore
import SwiftUI

struct JobDetailView: View {
    var plistPath: String
    var onEdit: (LaunchdJob) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var job: LaunchdJob?
    @State private var loadError: String?
    @State private var tab = DetailTab.configuration

    enum DetailTab: String, CaseIterable {
        case configuration = "Configuration"
        case logs = "Logs"
        case commands = "Commands"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if let job {
                Picker("", selection: $tab) {
                    ForEach(DetailTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(12)

                ScrollView {
                    Group {
                        switch tab {
                        case .configuration: ConfigurationTab(job: job)
                        case .logs: LogsTab(config: job.plist)
                        case .commands: CommandPanelView(job: job)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let loadError {
                Text(loadError).foregroundStyle(.red).padding()
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 640, height: 620)
        .task {
            do { job = try JobService.jobDetail(plistPath: plistPath) }
            catch { loadError = error.localizedDescription }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(job?.label ?? "Loading...")
                    .font(.headline)
                    .textSelection(.enabled)
                Spacer()
                Button("Done") { dismiss() }
            }

            if let job {
                HStack(spacing: 10) {
                    StatusBadge(status: job.status)
                    if let pid = job.pid {
                        Text("PID: \(pid)").font(.caption).foregroundStyle(.secondary)
                    }
                    if let exit = job.lastExitCode {
                        Text("Exit: \(exit)").font(.caption).foregroundStyle(.secondary)
                    }
                    if let lastRun = job.lastRunAt {
                        Text("Last run: \(Date(timeIntervalSince1970: lastRun / 1000).formatted())")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    if job.source == .userAgent {
                        Button("Edit") { onEdit(job) }
                    }
                    Button {
                        try? JobService.revealInFinder(path: job.plistPath)
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }
                }
            }
        }
        .padding(12)
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

private struct LogsTab: View {
    var config: PlistConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if config.standardOutPath == nil && config.standardErrorPath == nil {
                Text("No log paths configured for this agent")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let out = config.standardOutPath {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Standard Output").font(.callout.weight(.medium))
                    LogViewerView(logPath: out)
                }
            }
            if let err = config.standardErrorPath {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Standard Error").font(.callout.weight(.medium))
                    LogViewerView(logPath: err)
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

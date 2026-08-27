import LaunchdCore
import SwiftUI

struct ContentView: View {
    @Environment(JobsModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    @State private var creatingJob = false
    @State private var runTarget: JobListEntry?
    @State private var deleteTarget: JobListEntry?

    /// List selection is optional; the model's filter is not, so a nil selection
    /// (clicking empty sidebar space) is ignored rather than clearing the filter.
    private var filterSelection: Binding<SourceFilter?> {
        Binding(
            get: { model.sourceFilter },
            set: { if let new = $0 { model.sourceFilter = new } })
    }

    var body: some View {
        // The model arrives from the environment, so a local @Bindable is what supplies
        // the `$model.search` binding the search field needs.
        @Bindable var model = model

        return NavigationSplitView {
            List(selection: filterSelection) {
                Section("Source") {
                    ForEach(SourceFilter.allCases, id: \.self) { filter in
                        Label(filter.title, systemImage: filter.symbolName)
                            .tag(filter)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 260)
        } detail: {
            VStack(spacing: 0) {
                if let error = model.actionError {
                    ErrorBanner(message: error) { model.clearActionError() }
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                    Divider()
                }

                JobListView(
                    jobs: model.filteredJobs,
                    loading: model.loading,
                    onStart: { job in Task { await model.perform { try JobService.startJob(plistPath: job.plistPath) } } },
                    onStop: { job in Task { await model.perform { try JobService.stopJob(plistPath: job.plistPath) } } },
                    onRestart: { job in Task { await model.perform { try JobService.restartJob(plistPath: job.plistPath) } } },
                    onKickstart: { job in
                        // A dialog is only worth showing once options have been chosen
                        // for this job; otherwise Run Now stays the launchd kickstart
                        // it has always been.
                        if FlagStore.offeredFlags(for: job.label).isEmpty {
                            Task { await model.perform { try JobService.kickstartJob(label: job.label, plistPath: job.plistPath) } }
                        } else {
                            runTarget = job
                        }
                    },
                    onDelete: { deleteTarget = $0 },
                    onSelect: { openWindow(id: DetailWindow.id, value: $0.plistPath) },
                    onReveal: { job in try? JobService.revealInFinder(path: job.plistPath) }
                )
            }
            .frame(minWidth: 660, minHeight: 520)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh")

                Button {
                    creatingJob = true
                } label: {
                    Label("New Agent", systemImage: "plus")
                }
                .help("New Agent")
            }
            // Last item, so it sits at the trailing edge of the toolbar.
            ToolbarItem {
                ExpandingSearchField(text: $model.search)
            }
        }
        .task { await model.refresh() }
        .sheet(item: $runTarget) { job in
            RunOptionsSheet(entry: job)
        }
        .sheet(isPresented: $creatingJob) {
            JobFormView(editingJob: nil) { config, _ in
                _ = try JobService.createJob(label: config.label, config: config)
                Task { await model.refresh() }
            }
        }
        .alert("Delete Agent", isPresented: .constant(deleteTarget != nil), presenting: deleteTarget) { job in
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Delete", role: .destructive) {
                Task {
                    await model.perform { try JobService.deleteJob(plistPath: job.plistPath, label: job.label) }
                    deleteTarget = nil
                }
            }
        } message: { job in
            Text("Are you sure you want to delete \(job.label)? This will stop the agent and remove its plist file.")
        }
    }
}

struct ErrorBanner: View {
    var message: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(.red.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.red.opacity(0.4)))
    }
}

extension SourceFilter {
    var symbolName: String {
        switch self {
        case .all: "square.grid.2x2"
        case .userAgent: "person"
        case .home: "house"
        case .systemAgent: "gearshape"
        case .systemDaemon: "server.rack"
        }
    }
}

import LaunchdCore
import SwiftUI

struct ContentView: View {
    @State private var model = JobsModel()
    @State private var detailJob: JobListEntry?
    @State private var editingJob: LaunchdJob?
    @State private var creatingJob = false
    @State private var deleteTarget: JobListEntry?

    var body: some View {
        VStack(spacing: 0) {
            SearchBarView(search: $model.search, sourceFilter: $model.sourceFilter)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            if let error = model.loadError ?? model.actionError {
                ErrorBanner(message: error) { model.clearActionError() }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            Divider()

            JobListView(
                jobs: model.filteredJobs,
                loading: model.loading,
                onStart: { job in Task { await model.perform { try JobService.startJob(plistPath: job.plistPath) } } },
                onStop: { job in Task { await model.perform { try JobService.stopJob(plistPath: job.plistPath) } } },
                onRestart: { job in Task { await model.perform { try JobService.restartJob(plistPath: job.plistPath) } } },
                onKickstart: { job in
                    Task { await model.perform { try JobService.kickstartJob(label: job.label, plistPath: job.plistPath) } }
                },
                onDelete: { deleteTarget = $0 },
                onSelect: { detailJob = $0 },
                onReveal: { job in try? JobService.revealInFinder(path: job.plistPath) }
            )
        }
        .frame(minWidth: 860, minHeight: 520)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh")

                Button {
                    editingJob = nil
                    creatingJob = true
                } label: {
                    Label("New Agent", systemImage: "plus")
                }
                .help("New Agent")
            }
        }
        .task { await model.refresh() }
        .sheet(item: $detailJob) { job in
            JobDetailView(plistPath: job.plistPath) { loaded in
                detailJob = nil
                editingJob = loaded
            }
        }
        .sheet(isPresented: $creatingJob) {
            JobFormView(editingJob: nil) { config, _ in
                _ = try JobService.createJob(label: config.label, config: config)
                Task { await model.refresh() }
            }
        }
        .sheet(item: $editingJob) { job in
            JobFormView(editingJob: job) { config, plistPath in
                if let plistPath {
                    try JobService.saveJob(plistPath: plistPath, config: config)
                } else {
                    _ = try JobService.createJob(label: config.label, config: config)
                }
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

struct SearchBarView: View {
    @Binding var search: String
    @Binding var sourceFilter: SourceFilter

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search agents...", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
            .frame(maxWidth: 320)

            Picker("", selection: $sourceFilter) {
                ForEach(SourceFilter.allCases, id: \.self) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 380)

            Spacer()
        }
    }
}

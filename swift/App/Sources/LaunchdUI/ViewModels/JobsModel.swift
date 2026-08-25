import LaunchdCore
import Foundation
import Observation

/// Owns the job list, the search/filter state, and the results of user actions.
/// Replaces the `useJobs` hook plus the action/error state held in App.tsx.
@MainActor
@Observable
final class JobsModel {
    private(set) var jobs: [JobListEntry] = []
    private(set) var loading = true
    private(set) var actionError: String?

    var search = ""
    var sourceFilter: SourceFilter = .all

    var filteredJobs: [JobListEntry] {
        jobs.filter { job in
            let matchesSearch = search.isEmpty
                || job.label.range(of: search, options: .caseInsensitive) != nil
            let matchesSource: Bool
            switch sourceFilter {
            case .all: matchesSource = true
            case .home: matchesSource = job.isHomeAgent
            case .userAgent: matchesSource = job.source == .userAgent
            case .systemAgent: matchesSource = job.source == .systemAgent
            case .systemDaemon: matchesSource = job.source == .systemDaemon
            }
            return matchesSearch && matchesSource
        }
    }

    /// Scanning plists and shelling out to launchctl is blocking work, so it runs off the
    /// main actor; only the resulting state is published back.
    func refresh() async {
        loading = true
        let result = await Task.detached { JobService.listJobs() }.value
        jobs = result
        loading = false
    }

    /// Runs a job-control action off the main actor, surfaces any failure in the error
    /// banner, and refreshes the list either way so the UI reflects reality.
    func perform(_ action: @escaping @Sendable () throws -> Void) async {
        actionError = nil
        do {
            try await Task.detached { try action() }.value
        } catch {
            actionError = error.localizedDescription
        }
        await refresh()
    }

    func clearActionError() { actionError = nil }
}

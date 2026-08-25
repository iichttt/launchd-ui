import Foundation

/// The application's operations on launchd jobs. Mirrors the Tauri command surface in
/// src-tauri/src/commands.rs — one method per `#[tauri::command]`.
public enum JobService {

    // MARK: - Home-agent classification

    /// True when a program/argument path looks like a vendor app binary rather than a
    /// user-authored script: it lives in /Applications, inside an `.app` bundle, or under
    /// `~/Library/Application Support` (where auto-updaters install themselves).
    public static func isAppPath(_ path: String) -> Bool {
        path.hasPrefix("/Applications/")
            || path.contains(".app/")
            || path.contains("/Library/Application Support/")
    }

    /// True when `s` references a path under the user's home directory that is not itself
    /// an app-bundle path. `s` may be a bare path argument or a `zsh -c` command string
    /// with the path inside it.
    public static func referencesHomePath(_ s: String, home: String) -> Bool {
        s.contains(home) && !isAppPath(s)
    }

    /// Classifies a user agent as a "Home" agent: a user-authored automation (e.g. a shell
    /// or python script under `~/`) rather than a vendor-installed app. Requires that the
    /// launched executable is not an app bundle AND that some program path points under
    /// the home directory.
    public static func isHomeAgent(source: JobSource, config: PlistConfig, home: String) -> Bool {
        guard source == .userAgent, !home.isEmpty else { return false }

        // The executable actually launched: `Program`, else the first `ProgramArguments`
        // entry (which for scripts is usually the interpreter, e.g. /bin/bash).
        guard let executable = config.program ?? config.programArguments?.first else {
            return false
        }
        if isAppPath(executable) { return false }

        // Require at least one referenced path under the user's home directory (the script).
        var strings: [String] = []
        if let program = config.program { strings.append(program) }
        if let args = config.programArguments { strings.append(contentsOf: args) }
        return strings.contains { referencesHomePath($0, home: home) }
    }

    /// Milliseconds since the epoch of the newest of the job's two log files, or nil when
    /// neither exists — the app's stand-in for "when did this last run".
    public static func lastRunAt(config: PlistConfig) -> Double? {
        let paths = [config.standardOutPath, config.standardErrorPath].compactMap { $0 }
        var latest: Double?
        for path in paths {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let modified = attrs[.modificationDate] as? Date else { continue }
            let millis = modified.timeIntervalSince1970 * 1000
            latest = max(latest ?? millis, millis)
        }
        return latest
    }

    /// launchd job control is only safe for agents the user owns; system agents and
    /// daemons would need root and are rejected up front.
    private static func ensureUserAgent(_ plistPath: String) throws {
        let userAgents = PlistStore.userAgentsDirectory.path
        guard plistPath.hasPrefix(userAgents) else {
            throw AppError.launchctl(
                "Cannot start/stop system agents or daemons. Only user agents "
                    + "(~/Library/LaunchAgents) can be managed.")
        }
    }

    private static func source(forPlistPath path: String) -> JobSource {
        if path.contains("/Library/LaunchDaemons") { return .systemDaemon }
        if path.hasPrefix("/Library/LaunchAgents") { return .systemAgent }
        return .userAgent
    }

    // MARK: - Queries

    public static func listJobs() -> [JobListEntry] {
        let files = PlistStore.scanPlistFiles()
        let loaded = (try? Launchctl.listLoaded()) ?? []
        let loadedByLabel = Dictionary(loaded.map { ($0.label, $0) }, uniquingKeysWith: { a, _ in a })
        let home = PlistStore.homeDirectory.path

        var entries: [JobListEntry] = []
        for (path, source) in files {
            guard let config = try? PlistStore.parsePlist(atPath: path) else { continue }

            let status: JobStatus
            let pid: Int?
            let exitCode: Int?
            if let svc = loadedByLabel[config.label] {
                status = svc.pid != nil ? .running : .loaded
                pid = svc.pid
                exitCode = svc.lastExitCode
            } else {
                status = .unloaded
                pid = nil
                exitCode = nil
            }

            entries.append(
                JobListEntry(
                    label: config.label,
                    pid: pid,
                    lastExitCode: exitCode,
                    plistPath: path,
                    source: source,
                    status: status,
                    lastRunAt: lastRunAt(config: config),
                    isHomeAgent: isHomeAgent(source: source, config: config, home: home)
                ))
        }

        entries.sort { $0.label < $1.label }
        return entries
    }

    public static func jobDetail(plistPath: String) throws -> LaunchdJob {
        guard FileManager.default.fileExists(atPath: plistPath) else {
            throw AppError.notFound(plistPath)
        }

        let plist = try PlistStore.parsePlist(atPath: plistPath)
        let loaded = (try? Launchctl.listLoaded()) ?? []
        let svc = loaded.first { $0.label == plist.label }

        let status: JobStatus = svc == nil ? .unloaded : (svc?.pid != nil ? .running : .loaded)

        return LaunchdJob(
            label: plist.label,
            plistPath: plistPath,
            source: source(forPlistPath: plistPath),
            status: status,
            pid: svc?.pid,
            lastExitCode: svc?.lastExitCode,
            plist: plist,
            lastRunAt: lastRunAt(config: plist)
        )
    }

    // MARK: - Job control

    public static func startJob(plistPath: String) throws {
        try ensureUserAgent(plistPath)
        // Unload first to avoid "already loaded" or stale state.
        try? Launchctl.bootout(plistPath: plistPath)
        try Launchctl.bootstrap(plistPath: plistPath)
    }

    public static func stopJob(plistPath: String) throws {
        try ensureUserAgent(plistPath)
        try Launchctl.bootout(plistPath: plistPath)
    }

    public static func restartJob(plistPath: String) throws {
        try ensureUserAgent(plistPath)
        try? Launchctl.bootout(plistPath: plistPath)
        try Launchctl.bootstrap(plistPath: plistPath)
    }

    public static func kickstartJob(label: String, plistPath: String) throws {
        try ensureUserAgent(plistPath)
        // Ensure the service is loaded before kickstarting.
        let loaded = (try? Launchctl.listLoaded()) ?? []
        if !loaded.contains(where: { $0.label == label }) {
            try Launchctl.bootstrap(plistPath: plistPath)
        }
        try Launchctl.kickstart(label: label)
    }

    public static func enableJob(label: String) throws { try Launchctl.enable(label: label) }
    public static func disableJob(label: String) throws { try Launchctl.disable(label: label) }

    // MARK: - Mutation

    public static func saveJob(plistPath: String, config: PlistConfig) throws {
        try PlistStore.writePlist(atPath: plistPath, config: config)
    }

    public static func createJob(label: String, config: PlistConfig) throws -> String {
        let fm = FileManager.default
        let agentsDir = PlistStore.userAgentsDirectory
        if !fm.fileExists(atPath: agentsDir.path) {
            try fm.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        }
        // Create log directories if log paths are set, so launchd can open them.
        for logPath in [config.standardOutPath, config.standardErrorPath].compactMap({ $0 }) {
            let parent = URL(fileURLWithPath: logPath).deletingLastPathComponent()
            if !fm.fileExists(atPath: parent.path) {
                try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            }
        }
        let path = agentsDir.appending(path: "\(label).plist").path
        try PlistStore.writePlist(atPath: path, config: config)
        return path
    }

    public static func saveRawPlist(plistPath: String, xml: String) throws {
        try PlistStore.writeRawPlist(atPath: plistPath, xml: xml)
    }

    public static func deleteJob(plistPath: String, label: String) throws {
        try? Launchctl.bootout(plistPath: plistPath)
        try? Launchctl.disable(label: label)
        if FileManager.default.fileExists(atPath: plistPath) {
            try FileManager.default.removeItem(atPath: plistPath)
        }
    }

    // MARK: - Logs and Finder

    public static func readLogFile(path: String, tailLines: Int? = nil) throws -> LogFileResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            throw AppError.notFound("log file not found: \(path)")
        }

        let attrs = try fm.attributesOfItem(atPath: path)
        let modifiedAt = (attrs[.modificationDate] as? Date).map { $0.timeIntervalSince1970 * 1000 }

        guard let data = fm.contents(atPath: path) else {
            throw AppError.io("could not read \(path)")
        }
        var content = String(decoding: data, as: UTF8.self)
        if let n = tailLines {
            let lines = content.components(separatedBy: "\n")
            content = lines.suffix(n).joined(separator: "\n")
        }
        return LogFileResult(content: content, modifiedAt: modifiedAt)
    }

    public static func clearLogFile(path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw AppError.notFound("log file not found: \(path)")
        }
        try Data().write(to: URL(fileURLWithPath: path))
    }

    public static func openLogInEditor(path: String) throws {
        try Launchctl.run("/usr/bin/open", ["-t", path])
    }

    public static func revealInFinder(path: String) throws {
        try Launchctl.run("/usr/bin/open", ["-R", path])
    }
}

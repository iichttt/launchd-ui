import Foundation

/// Where a job's plist lives. Mirrors the Rust `JobSource` enum, including its
/// serialized spelling, so plists written by either implementation round-trip.
public enum JobSource: String, Codable, Sendable, CaseIterable {
    case userAgent = "UserAgent"
    case systemAgent = "SystemAgent"
    case systemDaemon = "SystemDaemon"
}

public enum JobStatus: String, Codable, Sendable {
    case running = "Running"
    case loaded = "Loaded"
    case unloaded = "Unloaded"
    case unknown = "Unknown"
}

/// Filter values for the source toolbar. `home` is a virtual filter (a subset of
/// `userAgent`) matching user-authored automations, driven by `JobListEntry.isHomeAgent`.
public enum SourceFilter: String, Hashable, CaseIterable, Sendable {
    case all = "All"
    case userAgent = "UserAgent"
    case home = "Home"
    case systemAgent = "SystemAgent"
    case systemDaemon = "SystemDaemon"

    public var title: String {
        switch self {
        case .all: "All"
        case .userAgent: "User"
        case .home: "Home"
        case .systemAgent: "System"
        case .systemDaemon: "Daemon"
        }
    }
}

public struct JobListEntry: Identifiable, Hashable, Sendable {
    public var label: String
    public var pid: Int?
    public var lastExitCode: Int?
    public var plistPath: String
    public var source: JobSource
    public var status: JobStatus
    /// Milliseconds since the Unix epoch, derived from the newest log file mtime.
    public var lastRunAt: Double?
    /// True when this looks like a user-authored automation (a script under the home
    /// directory), as opposed to a vendor-installed app. Drives the "Home" filter.
    public var isHomeAgent: Bool

    public var id: String { plistPath }

    public init(
        label: String, pid: Int? = nil, lastExitCode: Int? = nil, plistPath: String,
        source: JobSource, status: JobStatus, lastRunAt: Double? = nil, isHomeAgent: Bool
    ) {
        self.label = label
        self.pid = pid
        self.lastExitCode = lastExitCode
        self.plistPath = plistPath
        self.source = source
        self.status = status
        self.lastRunAt = lastRunAt
        self.isHomeAgent = isHomeAgent
    }
}

public struct CalendarInterval: Hashable, Sendable {
    public var minute: Int?
    public var hour: Int?
    public var day: Int?
    public var weekday: Int?
    public var month: Int?

    public var isEmpty: Bool {
        minute == nil && hour == nil && day == nil && weekday == nil && month == nil
    }

    public init(
        minute: Int? = nil, hour: Int? = nil, day: Int? = nil,
        weekday: Int? = nil, month: Int? = nil
    ) {
        self.minute = minute
        self.hour = hour
        self.day = day
        self.weekday = weekday
        self.month = month
    }
}

public struct PlistConfig: Hashable, Sendable {
    public var label: String
    public var program: String?
    public var programArguments: [String]?
    public var runAtLoad: Bool?
    public var keepAlive: Bool?
    public var startInterval: Int?
    public var startCalendarInterval: [CalendarInterval]?
    public var standardOutPath: String?
    public var standardErrorPath: String?
    public var workingDirectory: String?
    public var environmentVariables: [String: String]?
    public var disabled: Bool?
    public var wakeSystem: Bool?
    /// The plist exactly as it exists on disk (binary plists are converted to XML).
    public var rawXML: String

    public init(
        label: String,
        program: String? = nil,
        programArguments: [String]? = nil,
        runAtLoad: Bool? = nil,
        keepAlive: Bool? = nil,
        startInterval: Int? = nil,
        startCalendarInterval: [CalendarInterval]? = nil,
        standardOutPath: String? = nil,
        standardErrorPath: String? = nil,
        workingDirectory: String? = nil,
        environmentVariables: [String: String]? = nil,
        disabled: Bool? = nil,
        wakeSystem: Bool? = nil,
        rawXML: String = ""
    ) {
        self.label = label
        self.program = program
        self.programArguments = programArguments
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
        self.startInterval = startInterval
        self.startCalendarInterval = startCalendarInterval
        self.standardOutPath = standardOutPath
        self.standardErrorPath = standardErrorPath
        self.workingDirectory = workingDirectory
        self.environmentVariables = environmentVariables
        self.disabled = disabled
        self.wakeSystem = wakeSystem
        self.rawXML = rawXML
    }
}

public struct LaunchdJob: Identifiable, Hashable, Sendable {
    public var label: String
    public var plistPath: String
    public var source: JobSource
    public var status: JobStatus
    public var pid: Int?
    public var lastExitCode: Int?
    public var plist: PlistConfig
    public var lastRunAt: Double?

    public var id: String { plistPath }

    public init(
        label: String, plistPath: String, source: JobSource, status: JobStatus,
        pid: Int? = nil, lastExitCode: Int? = nil, plist: PlistConfig, lastRunAt: Double? = nil
    ) {
        self.label = label
        self.plistPath = plistPath
        self.source = source
        self.status = status
        self.pid = pid
        self.lastExitCode = lastExitCode
        self.plist = plist
        self.lastRunAt = lastRunAt
    }
}

public struct LogFileResult: Sendable {
    public var content: String
    /// Milliseconds since the Unix epoch.
    public var modifiedAt: Double?

    public init(content: String, modifiedAt: Double? = nil) {
        self.content = content
        self.modifiedAt = modifiedAt
    }
}

public enum AppError: LocalizedError, Equatable {
    case launchctl(String)
    case plist(String)
    case io(String)
    case notFound(String)

    public var errorDescription: String? {
        switch self {
        case .launchctl(let m): "launchctl error: \(m)"
        case .plist(let m): "plist error: \(m)"
        case .io(let m): "io error: \(m)"
        case .notFound(let m): "file not found: \(m)"
        }
    }
}

import Foundation

public struct LoadedService: Sendable {
    public var label: String
    public var pid: Int?
    public var lastExitCode: Int?

    public init(label: String, pid: Int? = nil, lastExitCode: Int? = nil) {
        self.label = label
        self.pid = pid
        self.lastExitCode = lastExitCode
    }
}

/// Thin wrapper around the `launchctl` CLI. Mirrors src-tauri/src/launchctl.rs.
public enum Launchctl {
    private static var guiTarget: String { "gui/\(getuid())" }

    private static func serviceTarget(_ label: String) -> String {
        "\(guiTarget)/\(label)"
    }

    public struct CommandResult {
        public var status: Int32
        public var stdout: String
        public var stderr: String
        public var succeeded: Bool { status == 0 }
    }

    @discardableResult
    public static func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw AppError.launchctl("failed to run \(executable): \(error.localizedDescription)")
        }

        // Drain both pipes before waiting so a large stdout cannot fill the pipe
        // buffer and deadlock the child.
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return CommandResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }

    private static func launchctl(_ arguments: [String]) throws -> CommandResult {
        try run("/bin/launchctl", arguments)
    }

    /// Parses `launchctl list` output: a header line followed by PID/Status/Label columns.
    public static func parseListOutput(_ output: String) -> [LoadedService] {
        var services: [LoadedService] = []
        for line in output.components(separatedBy: "\n").dropFirst() {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 3 else { continue }
            let label = parts[2].trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty else { continue }
            services.append(
                LoadedService(
                    label: label,
                    pid: Int(parts[0].trimmingCharacters(in: .whitespaces)),
                    lastExitCode: Int(parts[1].trimmingCharacters(in: .whitespaces))
                )
            )
        }
        return services
    }

    public static func listLoaded() throws -> [LoadedService] {
        let result = try launchctl(["list"])
        guard result.succeeded else {
            throw AppError.launchctl("launchctl list failed: \(result.stderr)")
        }
        return parseListOutput(result.stdout)
    }

    public static func bootstrap(plistPath: String) throws {
        let result = try launchctl(["bootstrap", guiTarget, plistPath])
        guard result.succeeded else {
            let stderr = result.stderr
            // "service already loaded" is not a fatal error
            if stderr.contains("already loaded") { return }
            let hint = stderr.contains("Input/output error")
                ? " Try re-running the command as root for richer errors."
                : ""
            throw AppError.launchctl("Bootstrap failed for \(plistPath): \(stderr)\(hint)")
        }
    }

    public static func bootout(plistPath: String) throws {
        let result = try launchctl(["bootout", guiTarget, plistPath])
        guard result.succeeded else {
            let stderr = result.stderr
            // "not loaded" is not a fatal error
            if stderr.contains("not loaded")
                || stderr.contains("No such process")
                || stderr.contains("Could not find specified service") { return }
            throw AppError.launchctl("launchctl bootout failed: \(stderr)")
        }
    }

    public static func kickstart(label: String) throws {
        let result = try launchctl(["kickstart", "-k", serviceTarget(label)])
        guard result.succeeded else {
            throw AppError.launchctl("launchctl kickstart failed: \(result.stderr)")
        }
    }

    public static func enable(label: String) throws {
        let result = try launchctl(["enable", serviceTarget(label)])
        guard result.succeeded else {
            throw AppError.launchctl("launchctl enable failed: \(result.stderr)")
        }
    }

    public static func disable(label: String) throws {
        let result = try launchctl(["disable", serviceTarget(label)])
        guard result.succeeded else {
            throw AppError.launchctl("launchctl disable failed: \(result.stderr)")
        }
    }
}

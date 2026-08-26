import Foundation

/// Builds the equivalent `launchctl` shell commands for a job, so users can copy what the
/// app would run. Mirrors src/components/CommandPanel.tsx.
public enum CommandBuilder {
    public struct CommandRow: Identifiable {
        public var label: String
        public var command: String
        public var destructive = false
        public var id: String { label }
    }

    /// Quotes a value for POSIX shells, leaving already-safe tokens untouched.
    public static func shellQuote(_ value: String) -> String {
        let safe = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
            + "abcdefghijklmnopqrstuvwxyz0123456789_@%+=:,./-")
        if !value.isEmpty, value.unicodeScalars.allSatisfy(safe.contains) { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func domain(for job: LaunchdJob) -> String {
        job.source == .systemDaemon ? "system" : "gui/$(id -u)"
    }

    private static func sudoPrefix(for job: LaunchdJob) -> String {
        job.source == .userAgent ? "" : "sudo "
    }

    public static func commands(for job: LaunchdJob) -> [CommandRow] {
        let prefix = sudoPrefix(for: job)
        let domain = domain(for: job)
        let target = "\(domain)/\(shellQuote(job.label))"
        let plistPath = shellQuote(job.plistPath)

        // Enable and Disable have no equivalent anywhere in the UI, so every job lists
        // them. The rest only earn their place on the read-only system jobs, where a
        // copied sudo command is the sole way to act; for a user agent they merely
        // restate the row buttons that already do the job in-app.
        let enablement = [
            CommandRow(label: "Enable", command: "\(prefix)launchctl enable \(target)"),
            CommandRow(label: "Disable", command: "\(prefix)launchctl disable \(target)"),
        ]
        guard job.source != .userAgent else { return enablement }

        return [
            CommandRow(label: "Start", command: "\(prefix)launchctl bootstrap \(domain) \(plistPath)"),
            CommandRow(label: "Stop", command: "\(prefix)launchctl bootout \(domain) \(plistPath)"),
            CommandRow(label: "Kickstart", command: "\(prefix)launchctl kickstart -k \(target)"),
        ] + enablement + [
            CommandRow(label: "Remove", command: "\(prefix)rm \(plistPath)", destructive: true),
        ]
    }
}

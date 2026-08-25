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

        return [
            CommandRow(label: "Start", command: "\(prefix)launchctl bootstrap \(domain) \(plistPath)"),
            CommandRow(label: "Stop", command: "\(prefix)launchctl bootout \(domain) \(plistPath)"),
            CommandRow(label: "Kickstart", command: "\(prefix)launchctl kickstart -k \(target)"),
            CommandRow(label: "Enable", command: "\(prefix)launchctl enable \(target)"),
            CommandRow(label: "Disable", command: "\(prefix)launchctl disable \(target)"),
            CommandRow(label: "Remove", command: "\(prefix)rm \(plistPath)", destructive: true),
        ]
    }
}

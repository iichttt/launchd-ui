import Foundation

/// A command-line option a job's program accepts.
public struct ProgramFlag: Identifiable, Hashable, Sendable, Codable {
    /// The long form where the program offers one, so `-v, --verbose` is stored as
    /// `--verbose`.
    public var name: String
    /// Non-nil when the option takes a value, carrying the program's own placeholder
    /// ("NAME" in `--library NAME`) to use as the field's prompt.
    public var valuePlaceholder: String?
    public var summary: String

    public var id: String { name }
    public var takesValue: Bool { valuePlaceholder != nil }

    public init(name: String, valuePlaceholder: String? = nil, summary: String = "") {
        self.name = name
        self.valuePlaceholder = valuePlaceholder
        self.summary = summary
    }
}

/// Learns a program's options by asking it for its own help text.
public enum FlagDiscovery {
    /// Runs the job's program with `--help` and reads the options out of what it prints.
    ///
    /// This executes the user's program. A program that does not understand `--help` may
    /// simply do its job instead, so the call is bounded by a deadline and its stdin is
    /// closed; it still cannot make an unhelpful program harmless.
    public static func discover(config: PlistConfig, timeout: TimeInterval = 10) throws -> [ProgramFlag] {
        guard let arguments = config.programArguments, let executable = arguments.first else {
            throw AppError.notFound("this job has no program to ask")
        }
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            // AppError.notFound already says "file not found", so the path alone reads
            // cleanly instead of stuttering the phrase twice.
            throw AppError.notFound(executable)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(arguments.dropFirst()) + ["--help"]
        if let directory = config.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
        }
        process.environment = environment(for: config)
        // Nothing to type at: a program that prompts would otherwise wait forever.
        process.standardInput = FileHandle.nullDevice

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw AppError.io("could not run \(executable): \(error.localizedDescription)")
        }

        let expired = Expired()
        let deadline = DispatchWorkItem {
            guard process.isRunning else { return }
            expired.value = true
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)

        // Drain before waiting: a help text larger than the pipe buffer would otherwise
        // deadlock the child against a parent that is waiting for it to exit.
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()

        if expired.value {
            throw AppError.io(
                "\(URL(fileURLWithPath: executable).lastPathComponent) did not answer --help "
                    + "within \(Int(timeout))s, so it probably does not support it")
        }

        // Plenty of programs print their usage to stderr, and some split it across both.
        let help = String(decoding: outData, as: UTF8.self)
            + "\n" + String(decoding: errData, as: UTF8.self)
        let flags = parse(help: help)
        guard !flags.isEmpty else {
            throw AppError.notFound("no options found in this program's --help output")
        }
        return flags
    }

    /// The environment a run of this job gets: the plist's own variables layered over the
    /// session's, so PATH and friends still resolve.
    public static func environment(for config: PlistConfig) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for (key, value) in config.environmentVariables ?? [:] { env[key] = value }
        return env
    }

    /// Pulls options out of help text. Kept separate from running anything so the shapes
    /// it accepts can be checked directly.
    public static func parse(help: String) -> [ProgramFlag] {
        var flags: [ProgramFlag] = []
        var seen = Set<String>()

        for rawLine in help.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            // Option lines are indented under a heading. A dash in column zero is prose
            // -- a wrapped sentence, or this file's own "--reset-state discards..." note.
            guard line.first == " " || line.first == "\t" else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("-") else { continue }

            let (options, summary) = splitColumns(trimmed)
            guard let flag = flag(from: options, summary: summary) else { continue }
            guard seen.insert(flag.name).inserted else { continue }
            flags.append(flag)
        }
        return flags
    }

    /// Splits an option line into its option block and its description. The gap between
    /// the two columns is two or more spaces; a single space still belongs to the option,
    /// as in `--library NAME`.
    private static func splitColumns(_ line: String) -> (String, String) {
        var index = line.startIndex
        while index < line.endIndex, let space = line[index...].firstIndex(of: " ") {
            let next = line.index(after: space)
            if next < line.endIndex, line[next] == " " {
                let description = line[next...].drop(while: { $0 == " " })
                return (String(line[..<space]), String(description))
            }
            index = next
        }
        return (line, "")
    }

    private static func flag(from options: String, summary: String) -> ProgramFlag? {
        let alternatives = options
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // Prefer the long form; a program offering only a short one is still listed.
        guard var name = alternatives.first(where: { $0.hasPrefix("--") }) ?? alternatives.first,
              name.hasPrefix("-")
        else { return nil }

        var placeholder: String?
        if let space = name.firstIndex(of: " ") {
            placeholder = String(name[name.index(after: space)...])
            name = String(name[..<space])
        }
        // `--limit=N` says the same thing as `--limit N`.
        if let equals = name.firstIndex(of: "=") {
            placeholder = String(name[name.index(after: equals)...])
            name = String(name[..<equals])
        }

        placeholder = placeholder?
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]<>"))
            .trimmingCharacters(in: .whitespaces)
        if placeholder?.isEmpty == true { placeholder = nil }

        guard name.count > 1 else { return nil }
        guard !helpAliases.contains(name) else { return nil }
        return ProgramFlag(name: name, valuePlaceholder: placeholder, summary: summary)
    }

    /// Offering these would only ever reprint the text we just parsed.
    private static let helpAliases: Set<String> = ["-h", "--help", "--usage"]

    /// A box the deadline can set from its own queue.
    private final class Expired: @unchecked Sendable {
        var value = false
    }
}

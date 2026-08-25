import Foundation

/// Reads and writes launchd plists. Mirrors src-tauri/src/plist_util.rs, but uses
/// Foundation's PropertyListSerialization instead of a third-party plist crate, which
/// also handles binary plists natively.
public enum PlistStore {
    public static var homeDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
    }

    public static var userAgentsDirectory: URL {
        homeDirectory.appending(path: "Library/LaunchAgents")
    }

    private static func plistDirectories() -> [(URL, JobSource)] {
        var dirs: [(URL, JobSource)] = [(userAgentsDirectory, .userAgent)]
        let fm = FileManager.default
        let systemAgents = URL(fileURLWithPath: "/Library/LaunchAgents")
        if fm.fileExists(atPath: systemAgents.path) {
            dirs.append((systemAgents, .systemAgent))
        }
        let systemDaemons = URL(fileURLWithPath: "/Library/LaunchDaemons")
        if fm.fileExists(atPath: systemDaemons.path) {
            dirs.append((systemDaemons, .systemDaemon))
        }
        return dirs
    }

    public static func scanPlistFiles() -> [(path: String, source: JobSource)] {
        var results: [(String, JobSource)] = []
        let fm = FileManager.default
        for (dir, source) in plistDirectories() {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for entry in entries where entry.hasSuffix(".plist") {
                results.append((dir.appending(path: entry).path, source))
            }
        }
        return results
    }

    // MARK: - Reading

    private static func dictionary(atPath path: String) throws -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw AppError.plist("\(path): could not read file")
        }
        let value: Any
        do {
            value = try PropertyListSerialization.propertyList(
                from: data, options: [], format: nil)
        } catch {
            throw AppError.plist("\(path): \(error.localizedDescription)")
        }
        guard let dict = value as? [String: Any] else {
            throw AppError.plist("\(path): not a dictionary")
        }
        return dict
    }

    /// launchd accepts both integers and booleans for numeric keys, and plists in the
    /// wild use either, so read numbers through NSNumber rather than a direct cast.
    private static func int(_ dict: [String: Any], _ key: String) -> Int? {
        (dict[key] as? NSNumber)?.intValue
    }

    private static func bool(_ dict: [String: Any], _ key: String) -> Bool? {
        (dict[key] as? NSNumber)?.boolValue
    }

    private static func string(_ dict: [String: Any], _ key: String) -> String? {
        dict[key] as? String
    }

    private static func calendarInterval(from dict: [String: Any]) -> CalendarInterval {
        CalendarInterval(
            minute: int(dict, "Minute"),
            hour: int(dict, "Hour"),
            day: int(dict, "Day"),
            weekday: int(dict, "Weekday"),
            month: int(dict, "Month")
        )
    }

    /// `StartCalendarInterval` may be a single dict or an array of them.
    private static func calendarIntervals(_ dict: [String: Any]) -> [CalendarInterval]? {
        guard let value = dict["StartCalendarInterval"] else { return nil }
        if let single = value as? [String: Any] {
            return [calendarInterval(from: single)]
        }
        if let array = value as? [[String: Any]] {
            let intervals = array.map(calendarInterval(from:))
            return intervals.isEmpty ? nil : intervals
        }
        return nil
    }

    public static func parsePlist(atPath path: String) throws -> PlistConfig {
        let dict = try dictionary(atPath: path)
        let label = string(dict, "Label")
            ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent

        return PlistConfig(
            label: label,
            program: string(dict, "Program"),
            programArguments: dict["ProgramArguments"] as? [String],
            runAtLoad: bool(dict, "RunAtLoad"),
            keepAlive: bool(dict, "KeepAlive"),
            startInterval: int(dict, "StartInterval"),
            startCalendarInterval: calendarIntervals(dict),
            standardOutPath: string(dict, "StandardOutPath"),
            standardErrorPath: string(dict, "StandardErrorPath"),
            workingDirectory: string(dict, "WorkingDirectory"),
            environmentVariables: dict["EnvironmentVariables"] as? [String: String],
            disabled: bool(dict, "Disabled"),
            wakeSystem: bool(dict, "WakeSystem"),
            rawXML: (try? readRawPlist(atPath: path)) ?? ""
        )
    }

    /// Returns the plist as XML text, converting binary plists on the fly.
    public static func readRawPlist(atPath path: String) throws -> String {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw AppError.io("could not read \(path)")
        }
        // Already XML? Return it verbatim so hand-written formatting survives a round trip.
        if data.starts(with: Array("<?xml".utf8)) || data.starts(with: Array("<".utf8)) {
            return String(decoding: data, as: UTF8.self)
        }
        let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let xml = try PropertyListSerialization.data(
            fromPropertyList: value, format: .xml, options: 0)
        return String(decoding: xml, as: UTF8.self)
    }

    // MARK: - Writing

    /// Builds the plist dictionary, omitting every key the config leaves unset so we
    /// never write defaults launchd would otherwise infer.
    public static func dictionary(from config: PlistConfig) -> [String: Any] {
        var dict: [String: Any] = ["Label": config.label]

        if let program = config.program { dict["Program"] = program }
        if let args = config.programArguments { dict["ProgramArguments"] = args }
        if let runAtLoad = config.runAtLoad { dict["RunAtLoad"] = runAtLoad }
        if let keepAlive = config.keepAlive { dict["KeepAlive"] = keepAlive }
        if let interval = config.startInterval { dict["StartInterval"] = interval }

        if let intervals = config.startCalendarInterval {
            dict["StartCalendarInterval"] = intervals.map { ci -> [String: Any] in
                var d: [String: Any] = [:]
                if let minute = ci.minute { d["Minute"] = minute }
                if let hour = ci.hour { d["Hour"] = hour }
                if let day = ci.day { d["Day"] = day }
                if let weekday = ci.weekday { d["Weekday"] = weekday }
                if let month = ci.month { d["Month"] = month }
                return d
            }
        }

        if let path = config.standardOutPath { dict["StandardOutPath"] = path }
        if let path = config.standardErrorPath { dict["StandardErrorPath"] = path }
        if let wd = config.workingDirectory { dict["WorkingDirectory"] = wd }
        if let env = config.environmentVariables { dict["EnvironmentVariables"] = env }
        if let disabled = config.disabled { dict["Disabled"] = disabled }
        if let wakeSystem = config.wakeSystem { dict["WakeSystem"] = wakeSystem }

        return dict
    }

    public static func writePlist(atPath path: String, config: PlistConfig) throws {
        let dict = dictionary(from: config)
        do {
            let data = try PropertyListSerialization.data(
                fromPropertyList: dict, format: .xml, options: 0)
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.plist("failed to write plist: \(error.localizedDescription)")
        }
    }

    /// Writes user-edited XML verbatim, but only after it parses as a plist.
    public static func writeRawPlist(atPath path: String, xml: String) throws {
        guard let data = xml.data(using: .utf8) else {
            throw AppError.plist("invalid plist XML: not valid UTF-8")
        }
        do {
            _ = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw AppError.plist("invalid plist XML: \(error.localizedDescription)")
        }
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

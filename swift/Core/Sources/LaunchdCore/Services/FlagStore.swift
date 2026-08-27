import Foundation

/// Remembers which of a program's options should be offered when running a job.
///
/// Kept beside the app rather than in the plist: this is a choice about what the run
/// dialog shows, not part of the job launchd runs, and writing it into the plist would
/// change the agent itself.
public enum FlagStore {
    public static var fileURL: URL {
        PlistStore.homeDirectory
            .appending(path: "Library/Application Support/launchd-ui/run-flags.json")
    }

    public static func offeredFlags(for label: String) -> [ProgramFlag] {
        all()[label] ?? []
    }

    public static func setOfferedFlags(_ flags: [ProgramFlag], for label: String) throws {
        var store = all()
        // An empty list is an absence, not an entry: it keeps the file from filling up
        // with labels the user has looked at and left alone.
        if flags.isEmpty { store.removeValue(forKey: label) } else { store[label] = flags }
        try write(store)
    }

    /// Unreadable or corrupt state is treated as "nothing configured" rather than an
    /// error: this is a convenience layer, and failing here would block the run dialog.
    public static func all() -> [String: [ProgramFlag]] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? JSONDecoder().decode([String: [ProgramFlag]].self, from: data)) ?? [:]
    }

    private static func write(_ store: [String: [ProgramFlag]]) throws {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(store).write(to: fileURL, options: .atomic)
        } catch {
            throw AppError.io("could not save run options: \(error.localizedDescription)")
        }
    }
}

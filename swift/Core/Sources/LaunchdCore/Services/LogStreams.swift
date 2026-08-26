import Foundation

/// One log file a job actually writes to.
public struct LogStream: Identifiable, Hashable, Sendable {
    public var title: String
    public var path: String
    public var id: String { title }

    public init(title: String, path: String) {
        self.title = title
        self.path = path
    }
}

extension PlistConfig {
    /// The distinct logs this job writes, named for how they are presented. A plist may
    /// give one path, two, or -- commonly -- the same path under both keys; that last
    /// case is one log written twice over, not two, and reads as a single "Log".
    public var logStreams: [LogStream] {
        if let out = standardOutPath, out == standardErrorPath {
            return [LogStream(title: "Log", path: out)]
        }
        var streams: [LogStream] = []
        if let out = standardOutPath { streams.append(LogStream(title: "Output", path: out)) }
        if let err = standardErrorPath { streams.append(LogStream(title: "Error", path: err)) }
        return streams
    }
}

import Foundation

/// Something the `memslop` command tells the app. One JSON file per event, so writers never race.
public struct InboxEvent: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        /// An agent session ended; `processes` are what it left running.
        case sessionEnded
        /// The command closed processes; `activity` goes into the log.
        case activity
    }

    public var kind: Kind
    public var date: Date
    public var agent: String?
    public var sessionID: String?
    public var processes: [ProcessIdentity]
    public var activity: [ActivityEntry]

    public init(kind: Kind, date: Date = Date(), agent: String? = nil, sessionID: String? = nil,
                processes: [ProcessIdentity] = [], activity: [ActivityEntry] = []) {
        self.kind = kind
        self.date = date
        self.agent = agent
        self.sessionID = sessionID
        self.processes = processes
        self.activity = activity
    }
}

/// A drop folder for `InboxEvent`s. Files are written atomically and deleted once read.
public struct Inbox: Sendable {
    public let directory: URL

    public init(directory: URL = StoragePaths.inbox) {
        self.directory = directory
    }

    @discardableResult
    public func post(_ event: InboxEvent) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(Int(event.date.timeIntervalSince1970 * 1000))-\(UUID().uuidString).json")
        try JSONEncoder.memslop.encode(event).write(to: url, options: .atomic)
        return url
    }

    /// Reads and removes every pending event, oldest first. Unreadable files are dropped.
    public func drain() -> [InboxEvent] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                defer { try? FileManager.default.removeItem(at: url) }
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder.memslop.decode(InboxEvent.self, from: data)
            }
    }

    /// True if any event is waiting (cheap enough to call every tick).
    public var hasPending: Bool {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).contains { $0.hasSuffix(".json") }
    }
}

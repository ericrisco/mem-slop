import Foundation

/// One thing the reaper (or the user) did.
public struct ActivityEntry: Identifiable, Sendable, Codable, Hashable {
    public enum Outcome: String, Sendable, Codable {
        case quit
        case forced
        case failed
        case wouldQuit
        case kept

        public var title: String {
            switch self {
            case .quit: "Closed"
            case .forced: "Force-closed"
            case .failed: "Failed"
            case .wouldQuit: "Dry run"
            case .kept: "Kept"
            }
        }

        public var freedMemory: Bool { self == .quit || self == .forced }
    }

    public var id: UUID
    public var date: Date
    public var name: String
    public var pid: Int32
    public var group: String
    public var rule: String
    public var reason: String
    public var memoryBytes: UInt64
    public var commandLine: String
    public var outcome: Outcome

    public init(id: UUID = UUID(), date: Date, name: String, pid: Int32, group: String, rule: String, reason: String,
                memoryBytes: UInt64, commandLine: String, outcome: Outcome) {
        self.id = id
        self.date = date
        self.name = name
        self.pid = pid
        self.group = group
        self.rule = rule
        self.reason = reason
        self.memoryBytes = memoryBytes
        self.commandLine = commandLine
        self.outcome = outcome
    }
}

/// Append-only activity log persisted as JSON, pruned to a retention window.
public struct ActivityLog: Sendable {
    public private(set) var entries: [ActivityEntry] = []
    public let retention: TimeInterval
    private let fileURL: URL?

    public init(fileURL: URL?, retention: TimeInterval = 24 * 3600) {
        self.fileURL = fileURL
        self.retention = retention
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder.memslop.decode([ActivityEntry].self, from: data) {
            entries = decoded
        }
        prune(now: Date())
    }

    public mutating func append(_ newEntries: [ActivityEntry], now: Date = Date()) {
        entries.append(contentsOf: newEntries)
        prune(now: now)
        save()
    }

    public mutating func prune(now: Date) {
        let retention = retention
        entries.removeAll { now.timeIntervalSince($0.date) > retention }
    }

    /// Memory freed by successful closes since `date`.
    public func freedMemory(since date: Date) -> UInt64 {
        entries.filter { $0.date >= date && $0.outcome.freedMemory }.reduce(0) { $0 + $1.memoryBytes }
    }

    public func save() {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder.memslop.encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

public enum StoragePaths {
    /// `~/Library/Application Support/MemSlop`
    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MemSlop", isDirectory: true)
    }

    public static var activityLog: URL { directory.appendingPathComponent("activity.json") }
    public static var history: URL { directory.appendingPathComponent("history.json") }
}

extension JSONEncoder {
    static var memslop: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var memslop: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

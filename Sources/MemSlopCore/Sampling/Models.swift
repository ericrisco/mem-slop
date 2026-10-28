import Darwin
import Foundation

/// Stable identity of a process. PIDs are recycled, so the start time is part of the key.
public struct ProcessIdentity: Hashable, Sendable, Codable, CustomStringConvertible {
    public let pid: Int32
    /// Process start time in microseconds since 1970.
    public let startTime: UInt64

    public init(pid: Int32, startTime: UInt64) {
        self.pid = pid
        self.startTime = startTime
    }

    public var description: String { "\(pid)@\(startTime)" }
}

/// One process at one sampling instant.
public struct ProcessSample: Identifiable, Hashable, Sendable {
    public let id: ProcessIdentity
    public let ppid: Int32
    public let uid: UInt32
    /// Short process name (executable file name).
    public let name: String
    public let executablePath: String
    public let arguments: [String]
    /// CPU usage like Activity Monitor: 100 = one full core.
    public let cpuPercent: Double
    /// Physical footprint in bytes (Activity Monitor's "Memory" column).
    public let memoryBytes: UInt64
    /// Cumulative user + system CPU time in nanoseconds.
    public let cpuTimeNanos: UInt64
    public let startDate: Date
    /// The full command line, falling back to the executable path.
    public let commandLine: String
    /// Lowercased copies for matching and search, computed once per sample.
    public let matchKeys: MatchKeys
    /// Ports and project; filled in only while someone is looking at the list.
    public var context: ProcessContext = .empty

    public struct MatchKeys: Hashable, Sendable {
        public let name: String
        public let commandLine: ByteText
        public let path: ByteText
    }

    public var pid: Int32 { id.pid }

    public init(
        id: ProcessIdentity, ppid: Int32, uid: UInt32, name: String, executablePath: String,
        arguments: [String], cpuPercent: Double, memoryBytes: UInt64, cpuTimeNanos: UInt64,
        startDate: Date
    ) {
        self.id = id
        self.ppid = ppid
        self.uid = uid
        self.name = name
        self.executablePath = executablePath
        self.arguments = arguments
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.cpuTimeNanos = cpuTimeNanos
        self.startDate = startDate
        let commandLine = arguments.isEmpty ? executablePath : arguments.joined(separator: " ")
        self.commandLine = commandLine
        matchKeys = MatchKeys(name: name.lowercased(), commandLine: ByteText(commandLine), path: ByteText(executablePath))
    }
}

/// A lightweight node of the full process tree, including processes owned by other users.
/// Used to walk ancestry (e.g. a shell whose parent is the root-owned `login`).
public struct ProcessNode: Hashable, Sendable {
    public let pid: Int32
    public let ppid: Int32
    public let name: String
    public let executablePath: String

    public init(pid: Int32, ppid: Int32, name: String, executablePath: String) {
        self.pid = pid
        self.ppid = ppid
        self.name = name
        self.executablePath = executablePath
    }
}

public enum MemoryPressure: Int, Sendable, Codable, Comparable {
    case normal = 1
    case warning = 2
    case critical = 4

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// System-wide load at one instant.
public struct SystemSnapshot: Hashable, Sendable {
    /// Total CPU usage across all cores, 0...1.
    public var cpuUsage: Double
    public var cpuUser: Double
    public var cpuSystem: Double
    public var coreCount: Int
    public var memoryTotal: UInt64
    /// App + wired + compressed, like Activity Monitor's "Memory Used".
    public var memoryUsed: UInt64
    public var memoryApp: UInt64
    public var memoryWired: UInt64
    public var memoryCompressed: UInt64
    public var memoryCached: UInt64
    public var swapUsed: UInt64
    public var pressure: MemoryPressure
    public var loadAverage: [Double]

    public init(
        cpuUsage: Double = 0, cpuUser: Double = 0, cpuSystem: Double = 0, coreCount: Int = 1,
        memoryTotal: UInt64 = 0, memoryUsed: UInt64 = 0, memoryApp: UInt64 = 0,
        memoryWired: UInt64 = 0, memoryCompressed: UInt64 = 0, memoryCached: UInt64 = 0,
        swapUsed: UInt64 = 0, pressure: MemoryPressure = .normal, loadAverage: [Double] = [0, 0, 0]
    ) {
        self.cpuUsage = cpuUsage
        self.cpuUser = cpuUser
        self.cpuSystem = cpuSystem
        self.coreCount = coreCount
        self.memoryTotal = memoryTotal
        self.memoryUsed = memoryUsed
        self.memoryApp = memoryApp
        self.memoryWired = memoryWired
        self.memoryCompressed = memoryCompressed
        self.memoryCached = memoryCached
        self.swapUsed = swapUsed
        self.pressure = pressure
        self.loadAverage = loadAverage
    }

    /// Memory used, 0...1.
    public var memoryUsage: Double {
        memoryTotal == 0 ? 0 : min(1, Double(memoryUsed) / Double(memoryTotal))
    }
}

/// Everything one sampling tick produces.
public struct MonitorSnapshot: Sendable {
    public let timestamp: Date
    public let system: SystemSnapshot
    /// Processes owned by the current user that could be inspected.
    public let processes: [ProcessSample]
    /// Every visible process, for ancestry walks.
    public let tree: [Int32: ProcessNode]

    public init(timestamp: Date, system: SystemSnapshot, processes: [ProcessSample], tree: [Int32: ProcessNode]) {
        self.timestamp = timestamp
        self.system = system
        self.processes = processes
        self.tree = tree
    }

    public static let empty = MonitorSnapshot(timestamp: .distantPast, system: SystemSnapshot(), processes: [], tree: [:])
}

/// Lowercased UTF-8 bytes with a fast substring search (`memmem`), for matching long command lines.
public struct ByteText: Hashable, Sendable {
    public let bytes: [UInt8]

    public init(_ text: String) {
        bytes = Array(text.lowercased().utf8)
    }

    /// `needle` must already be lowercased.
    public func contains(_ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty else { return true }
        guard needle.count <= bytes.count else { return false }
        return bytes.withUnsafeBytes { haystack in
            needle.withUnsafeBytes { pattern in
                memmem(haystack.baseAddress, haystack.count, pattern.baseAddress, pattern.count) != nil
            }
        }
    }

    public func contains(_ needle: String) -> Bool {
        contains(Array(needle.lowercased().utf8))
    }
}

import Foundation

/// A set of related processes shown as one expandable row.
public struct ProcessGroup: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Processes living inside an application bundle (path of the outermost `.app`).
        case app(bundlePath: String)
        case family(ProcessFamily)
        case executable
    }

    public let id: String
    public let name: String
    public let kind: Kind
    public var processes: [ProcessSample]

    public init(id: String, name: String, kind: Kind, processes: [ProcessSample]) {
        self.id = id
        self.name = name
        self.kind = kind
        self.processes = processes
    }

    public var cpuPercent: Double { processes.reduce(0) { $0 + $1.cpuPercent } }
    public var memoryBytes: UInt64 { processes.reduce(0) { $0 + $1.memoryBytes } }
    public var bundlePath: String? {
        if case let .app(path) = kind { return path }
        return nil
    }
}

public enum SortKey: String, CaseIterable, Sendable, Codable {
    case cpu
    case memory
}

/// Groups processes by app bundle, family or executable name.
public struct ProcessGrouper: Sendable {
    public init() {}

    public func group(_ processes: [ProcessSample], sortedBy key: SortKey) -> [ProcessGroup] {
        var groups: [String: ProcessGroup] = [:]
        for process in processes {
            let (id, name, kind) = Self.classify(process)
            groups[id, default: ProcessGroup(id: id, name: name, kind: kind, processes: [])].processes.append(process)
        }
        return groups.values
            .map { group in
                var group = group
                group.processes.sort { Self.ordered($0, $1, by: key) }
                return group
            }
            .sorted { lhs, rhs in
                switch key {
                case .cpu:
                    lhs.cpuPercent != rhs.cpuPercent ? lhs.cpuPercent > rhs.cpuPercent : lhs.memoryBytes > rhs.memoryBytes
                case .memory:
                    lhs.memoryBytes != rhs.memoryBytes ? lhs.memoryBytes > rhs.memoryBytes : lhs.cpuPercent > rhs.cpuPercent
                }
            }
    }

    static func ordered(_ lhs: ProcessSample, _ rhs: ProcessSample, by key: SortKey) -> Bool {
        switch key {
        case .cpu: lhs.cpuPercent != rhs.cpuPercent ? lhs.cpuPercent > rhs.cpuPercent : lhs.memoryBytes > rhs.memoryBytes
        case .memory: lhs.memoryBytes != rhs.memoryBytes ? lhs.memoryBytes > rhs.memoryBytes : lhs.cpuPercent > rhs.cpuPercent
        }
    }

    static func classify(_ process: ProcessSample) -> (id: String, name: String, kind: ProcessGroup.Kind) {
        if let family = ProcessFamily.detect(name: process.name, arguments: process.arguments) {
            return ("family:\(family.rawValue)", family.displayName, .family(family))
        }
        if let bundle = outermostAppBundle(in: process.executablePath) {
            return ("app:\(bundle)", AppNames.shared.name(forBundleAt: bundle), .app(bundlePath: bundle))
        }
        let name = process.name.isEmpty ? "pid \(process.pid)" : process.name
        return ("exe:\(name)", name, .executable)
    }

    /// `/Applications/Google Chrome.app/Contents/Frameworks/.../Helper.app/...` → `/Applications/Google Chrome.app`
    public static func outermostAppBundle(in path: String) -> String? {
        guard let range = path.range(of: ".app/") else {
            return path.hasSuffix(".app") ? path : nil
        }
        return String(path[..<range.lowerBound]) + ".app"
    }
}

/// Caches human names of app bundles (CFBundleDisplayName / CFBundleName).
public final class AppNames: @unchecked Sendable {
    public static let shared = AppNames()
    private var cache: [String: String] = [:]
    private let lock = NSLock()

    public func name(forBundleAt path: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        if let name = cache[path] { return name }
        let info = Bundle(path: path)?.infoDictionary
        let name = (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        cache[path] = name
        return name
    }
}

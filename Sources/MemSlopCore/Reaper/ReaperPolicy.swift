import Foundation

public struct ReaperConfiguration: Sendable, Codable, Equatable {
    public static let intervalChoices = [10, 15, 20, 30, 60]

    public var isEnabled = true
    /// Sweep interval and idle window, in minutes.
    public var intervalMinutes = 10
    /// Average CPU (100 = one core) below which a process counts as idle.
    public var cpuThreshold = 0.5
    /// Allowed memory change over the window, as a fraction of the peak…
    public var memoryChangeFraction = 0.05
    /// …but never less than this many bytes.
    public var memoryChangeFloor: UInt64 = 10 * 1_048_576
    public var notifyBefore = true
    public var graceSeconds = 60
    public var dryRun = false
    public var rules = ProcessRule.defaultSlop
    public var protected = ProcessRule.defaultProtected
    /// Sweep early, with a shorter idle window, when memory pressure stays critical.
    public var cleanOnPressure = true
    /// Testing aid: replaces the interval-based window (seconds). Never set from the UI.
    public var windowOverride: TimeInterval?

    /// Under critical pressure a process only needs to be idle this long (or the interval, if shorter).
    public static let pressureWindow: TimeInterval = 5 * 60
    /// How long pressure must stay critical before an early sweep.
    public static let pressureDelay: TimeInterval = 30
    /// Minimum time between two pressure sweeps.
    public static let pressureCooldown: TimeInterval = 5 * 60

    public init() {}

    public var window: TimeInterval { windowOverride ?? TimeInterval(intervalMinutes * 60) }
    public var pressureWindow: TimeInterval { min(window, Self.pressureWindow) }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, intervalMinutes, cpuThreshold, memoryChangeFraction, memoryChangeFloor, notifyBefore
        case graceSeconds, dryRun, rules, protected, cleanOnPressure
    }

    /// Settings saved by older versions lack newer keys; every key falls back to its default.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ReaperConfiguration()
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? defaults.isEnabled
        intervalMinutes = try container.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? defaults.intervalMinutes
        cpuThreshold = try container.decodeIfPresent(Double.self, forKey: .cpuThreshold) ?? defaults.cpuThreshold
        memoryChangeFraction = try container.decodeIfPresent(Double.self, forKey: .memoryChangeFraction) ?? defaults.memoryChangeFraction
        memoryChangeFloor = try container.decodeIfPresent(UInt64.self, forKey: .memoryChangeFloor) ?? defaults.memoryChangeFloor
        notifyBefore = try container.decodeIfPresent(Bool.self, forKey: .notifyBefore) ?? defaults.notifyBefore
        graceSeconds = try container.decodeIfPresent(Int.self, forKey: .graceSeconds) ?? defaults.graceSeconds
        dryRun = try container.decodeIfPresent(Bool.self, forKey: .dryRun) ?? defaults.dryRun
        rules = try container.decodeIfPresent([ProcessRule].self, forKey: .rules) ?? defaults.rules
        protected = try container.decodeIfPresent([ProcessRule].self, forKey: .protected) ?? defaults.protected
        cleanOnPressure = try container.decodeIfPresent(Bool.self, forKey: .cleanOnPressure) ?? defaults.cleanOnPressure
    }
}

/// A process the reaper wants to close, with the evidence for it.
public struct ReapCandidate: Identifiable, Sendable, Hashable {
    public let process: ProcessSample
    public let rule: String
    public let ancestry: Ancestry
    public let averageCPU: Double
    public let idleFor: TimeInterval

    public var id: ProcessIdentity { process.id }

    public init(process: ProcessSample, rule: String, ancestry: Ancestry, averageCPU: Double, idleFor: TimeInterval) {
        self.process = process
        self.rule = rule
        self.ancestry = ancestry
        self.averageCPU = averageCPU
        self.idleFor = idleFor
    }
}

/// Pure decision logic: given what we see, which processes are idle dev slop?
public struct ReaperPolicy: Sendable {
    public let configuration: ReaperConfiguration
    private let rules: [CompiledRule]
    private let protected: [CompiledRule]

    public init(configuration: ReaperConfiguration) {
        self.configuration = configuration
        rules = configuration.rules.compactMap(CompiledRule.init)
        protected = configuration.protected.compactMap(CompiledRule.init)
    }

    /// The first enabled slop rule that matches, ignoring idleness and ancestry.
    public func matchingRule(for process: ProcessSample) -> ProcessRule? {
        rules.first { $0.matches(process) }?.rule
    }

    public func isProtected(_ process: ProcessSample) -> Bool {
        protected.contains { $0.matches(process) }
    }

    /// - Parameters:
    ///   - regularAppPIDs: PIDs of regular GUI apps (Dock icon). They are never candidates unless the
    ///     matching rule explicitly allows apps.
    ///   - kept: processes the user chose to keep.
    public func candidates(
        in snapshot: MonitorSnapshot,
        tracker: IdleTracker,
        regularAppPIDs: Set<Int32>,
        kept: Set<ProcessIdentity>,
        excluding excludedPIDs: Set<Int32> = [],
        window: TimeInterval? = nil,
        now: Date
    ) -> [ReapCandidate] {
        let window = window ?? configuration.window
        let arguments = Dictionary(snapshot.processes.map { ($0.pid, $0.arguments) }, uniquingKeysWith: { first, _ in first })
        let byPID = Dictionary(snapshot.processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var children: [Int32: [Int32]] = [:]
        for node in snapshot.tree.values { children[node.ppid, default: []].append(node.pid) }

        func isIdle(_ process: ProcessSample) -> IdleTracker.Activity? {
            guard let activity = tracker.activity(of: process, over: window, now: now) else { return nil }
            let allowedChange = max(UInt64(Double(activity.peakMemory) * configuration.memoryChangeFraction), configuration.memoryChangeFloor)
            guard activity.averageCPU < configuration.cpuThreshold, activity.memoryChange <= allowedChange else { return nil }
            return activity
        }

        func descendantsAreIdle(_ pid: Int32, depth: Int = 0) -> Bool {
            guard depth < 32 else { return false }
            for child in children[pid] ?? [] {
                guard let process = byPID[child] else { continue }
                if isIdle(process) == nil { return false }
                if !descendantsAreIdle(child, depth: depth + 1) { return false }
            }
            return true
        }

        return snapshot.processes.compactMap { process in
            guard !excludedPIDs.contains(process.pid), !kept.contains(process.id),
                  let rule = matchingRule(for: process), !isProtected(process) else { return nil }
            if regularAppPIDs.contains(process.pid), !rule.matchesApps { return nil }
            let ancestry = AncestryClassifier.classify(process, tree: snapshot.tree, arguments: arguments)
            guard ancestry.isEligible, let activity = isIdle(process), descendantsAreIdle(process.pid) else { return nil }
            return ReapCandidate(process: process, rule: rule.name, ancestry: ancestry, averageCPU: activity.averageCPU, idleFor: activity.observedFor)
        }
        .sorted { $0.process.memoryBytes > $1.process.memoryBytes }
    }
}

public extension ReaperPolicy {
    /// CPU time a pending candidate may burn during the grace period and still be closed.
    /// An idle server burns close to nothing; serving a single request costs more than this.
    static let graceCPUAllowanceNanos: UInt64 = 50_000_000

    /// True if the process did real work between being announced and being closed.
    static func wasActive(before: ProcessSample, after: ProcessSample, memoryFloor: UInt64) -> Bool {
        let cpu = after.cpuTimeNanos >= before.cpuTimeNanos ? after.cpuTimeNanos - before.cpuTimeNanos : 0
        let memory = after.memoryBytes > before.memoryBytes ? after.memoryBytes - before.memoryBytes : before.memoryBytes - after.memoryBytes
        return cpu > graceCPUAllowanceNanos || memory > memoryFloor
    }
}

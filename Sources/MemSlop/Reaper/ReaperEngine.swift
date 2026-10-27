import AppKit
import MemSlopCore
import Observation

/// Runs the auto-clean cycle: sweep → announce → grace period → close → log.
@MainActor @Observable
final class ReaperEngine {
    var configuration: ReaperConfiguration {
        didSet {
            if !DemoData.isEnabled { Self.save(configuration) }
            if configuration.intervalMinutes != oldValue.intervalMinutes || configuration.isEnabled != oldValue.isEnabled {
                cancelPending()
                nextSweep = Date().addingTimeInterval(configuration.window)
            }
        }
    }

    private(set) var nextSweep: Date
    private(set) var pending: [ReapCandidate] = []
    private(set) var pendingDeadline: Date?
    private(set) var kept: Set<ProcessIdentity> = []
    private(set) var log: ActivityLog
    private(set) var lastSweep: Date?
    private(set) var lastSummary: String?
    private(set) var isClosing = false

    @ObservationIgnored private var tracker = IdleTracker()
    @ObservationIgnored private let terminator = ProcessTerminator()
    @ObservationIgnored private let notifier: ReaperNotifier
    @ObservationIgnored private var sweepRequested = false
    /// `--reaper-dry-run`: never closes anything this session, whatever the settings say.
    @ObservationIgnored private let forceDryRun: Bool

    var isDryRun: Bool { configuration.dryRun || forceDryRun }

    var policy: ReaperPolicy { ReaperPolicy(configuration: configuration) }

    init() {
        var configuration = Self.load()
        configuration.windowOverride = Self.testWindow()
        forceDryRun = CommandLine.arguments.contains("--reaper-dry-run") || DemoData.isEnabled
        self.configuration = configuration
        nextSweep = Date().addingTimeInterval(configuration.window)
        log = ActivityLog(fileURL: DemoData.isEnabled ? nil : StoragePaths.activityLog)
        notifier = ReaperNotifier()
        notifier.onKeepAll = { [weak self] in self?.keepAll() }
        notifier.onCloseNow = { [weak self] in self?.closeNow() }
        if DemoData.isEnabled { log.append(DemoData.activity(now: Date())) }
    }

    /// Demo only: shows a pending cleanup without ever closing anything.
    func showDemoPending(_ snapshot: MonitorSnapshot) {
        guard DemoData.isEnabled else { return }
        let rules = policy
        var families = Set<String>()
        pending = snapshot.processes.compactMap { process in
            guard let rule = rules.matchingRule(for: process), !rules.isProtected(process), process.cpuPercent < 1,
                  families.insert(ProcessGrouper.classify(process).id).inserted else { return nil }
            let ancestry: Ancestry = process.name == "node" ? .agentSpawned(agent: "Claude Code")
                : process.name.hasPrefix("python") ? .agentSpawned(agent: "Codex") : .orphaned
            return ReapCandidate(process: process, rule: rule.name, ancestry: ancestry, averageCPU: 0, idleFor: 1500)
        }
        pendingDeadline = Date().addingTimeInterval(47)
        nextSweep = Date().addingTimeInterval(600)
    }

    /// Memory freed by successful closes since local midnight.
    var freedToday: UInt64 { log.freedMemory(since: Calendar.current.startOfDay(for: Date())) }

    func isPending(_ identity: ProcessIdentity) -> Bool { pending.contains { $0.id == identity } }

    // MARK: - Cycle

    /// Called after every sampling tick.
    func observe(_ snapshot: MonitorSnapshot, processesSampled: Bool) {
        let now = snapshot.timestamp
        guard processesSampled else { return }
        tracker.record(snapshot.processes, at: now)
        let alive = Set(snapshot.processes.map(\.id))
        kept.formIntersection(alive)
        pending.removeAll { !alive.contains($0.id) }
        if pending.isEmpty, pendingDeadline != nil { pendingDeadline = nil }

        guard configuration.isEnabled, !isClosing, !DemoData.isEnabled else { return }
        if let deadline = pendingDeadline {
            if now >= deadline { close(using: snapshot) }
        } else if sweepRequested || now >= nextSweep {
            sweep(snapshot)
        }
    }

    func requestSweep() {
        sweepRequested = true
    }

    private func sweep(_ snapshot: MonitorSnapshot) {
        sweepRequested = false
        let now = snapshot.timestamp
        lastSweep = now
        let candidates = policy.candidates(
            in: snapshot, tracker: tracker, regularAppPIDs: Self.regularAppPIDs(), kept: kept,
            excluding: [getpid()], now: now
        )
        guard !candidates.isEmpty else {
            lastSummary = "Nothing idle to clean"
            nextSweep = now.addingTimeInterval(configuration.window)
            return
        }
        pending = candidates
        if configuration.notifyBefore, !isDryRun {
            pendingDeadline = now.addingTimeInterval(TimeInterval(configuration.graceSeconds))
            notifier.announce(candidates, in: configuration.graceSeconds)
        } else {
            pendingDeadline = now
            close(using: snapshot)
        }
    }

    private func close(using snapshot: MonitorSnapshot) {
        let now = snapshot.timestamp
        let current = Dictionary(snapshot.processes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let fresh = Set(policy.candidates(
            in: snapshot, tracker: tracker, regularAppPIDs: Self.regularAppPIDs(), kept: kept,
            excluding: [getpid()], now: now
        ).map(\.id))
        let targets = pending.filter { candidate in
            guard fresh.contains(candidate.id), !kept.contains(candidate.id), let latest = current[candidate.id] else { return false }
            return !ReaperPolicy.wasActive(before: candidate.process, after: latest, memoryFloor: configuration.memoryChangeFloor)
        }
        let spared = pending.count - targets.count
        pending = []
        pendingDeadline = nil
        nextSweep = now.addingTimeInterval(configuration.window)

        if isDryRun {
            record(targets.map { ($0, ActivityEntry.Outcome.wouldQuit) })
            lastSummary = targets.isEmpty ? "Nothing idle to clean" : "Dry run: would close \(targets.count)"
            return
        }
        guard !targets.isEmpty else {
            lastSummary = spared > 0 ? "Spared \(spared) that woke up" : "Nothing idle to clean"
            return
        }
        isClosing = true
        Task {
            let results = await terminator.terminate(targets.map(\.id))
            let outcomes: [(ReapCandidate, ActivityEntry.Outcome)] = targets.map { candidate in
                switch results[candidate.id] {
                case .terminated?, .notRunning?: (candidate, .quit)
                case .killed?: (candidate, .forced)
                default: (candidate, .failed)
                }
            }
            record(outcomes)
            let closed = outcomes.filter { $0.1.freedMemory }
            let freed = closed.reduce(UInt64(0)) { $0 + $1.0.process.memoryBytes }
            lastSummary = "Closed \(closed.count) · freed \(Formatting.bytes(freed))"
            notifier.report(closed: closed.count, freed: freed)
            isClosing = false
        }
    }

    private func record(_ outcomes: [(ReapCandidate, ActivityEntry.Outcome)]) {
        guard !outcomes.isEmpty else { return }
        let entries = outcomes.map { candidate, outcome in
            ActivityEntry(
                date: Date(), name: candidate.process.name, pid: candidate.process.pid,
                group: ProcessGrouper.classify(candidate.process).name, rule: candidate.rule,
                reason: candidate.ancestry.label, memoryBytes: candidate.process.memoryBytes,
                commandLine: candidate.process.commandLine, outcome: outcome
            )
        }
        log.append(entries)
    }

    // MARK: - User actions

    func keep(_ identity: ProcessIdentity) {
        if let candidate = pending.first(where: { $0.id == identity }) {
            record([(candidate, .kept)])
        }
        kept.insert(identity)
        pending.removeAll { $0.id == identity }
        if pending.isEmpty { cancelPending() }
    }

    func keepAll() {
        for candidate in pending { keep(candidate.id) }
    }

    /// Skips the rest of the grace period.
    func closeNow() {
        guard pendingDeadline != nil else { return }
        pendingDeadline = .distantPast
    }

    private func cancelPending() {
        pending = []
        pendingDeadline = nil
        notifier.withdraw()
    }

    func restoreDefaultRules() {
        configuration.rules = ProcessRule.defaultSlop
    }

    func restoreDefaultProtected() {
        configuration.protected = ProcessRule.defaultProtected
    }

    // MARK: - Helpers

    /// `--reaper-test-window=60` shortens the idle window to try the cycle end to end.
    private static func testWindow() -> TimeInterval? {
        CommandLine.arguments.lazy
            .compactMap { $0.hasPrefix("--reaper-test-window=") ? TimeInterval($0.dropFirst("--reaper-test-window=".count)) : nil }
            .first
    }

    static func regularAppPIDs() -> Set<Int32> {
        Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map(\.processIdentifier))
    }

    private static let defaultsKey = "reaperConfiguration"

    private static func load() -> ReaperConfiguration {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let configuration = try? JSONDecoder().decode(ReaperConfiguration.self, from: data) else {
            return ReaperConfiguration()
        }
        return configuration
    }

    private static func save(_ configuration: ReaperConfiguration) {
        if let data = try? JSONEncoder().encode(configuration) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

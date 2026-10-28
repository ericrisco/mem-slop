import AppKit
import MemSlopCore
import Observation

/// The UI's single source of truth. Owns the sampling loop and every user action.
@MainActor @Observable
final class AppModel {
    static let trendLength = 90

    private(set) var snapshot: MonitorSnapshot = .empty
    private(set) var system = SystemSnapshot()
    private(set) var groups: [ProcessGroup] = []
    private(set) var cpuTrend: [Double] = []
    private(set) var memoryTrend: [Double] = []

    var sortKey: SortKey = Preferences.sortKey {
        didSet { Preferences.sortKey = sortKey; regroup() }
    }
    var groupingMode: GroupingMode = Preferences.groupingMode {
        didSet { Preferences.groupingMode = groupingMode; regroup() }
    }
    var searchText = "" {
        didSet { regroup() }
    }
    var displayStyle: DisplayStyle = Preferences.displayStyle {
        didSet { Preferences.displayStyle = displayStyle; onIndicatorChange?() }
    }
    var refreshInterval: Double = Preferences.refreshInterval {
        didSet { Preferences.refreshInterval = refreshInterval }
    }

    var expandedGroups: Set<String> = []
    var selection: Set<ProcessIdentity> = []
    private(set) var quitting: Set<ProcessIdentity> = []
    private(set) var errors: [ProcessIdentity: String] = [:]

    /// True while the panel lists processes; the process table is then refreshed every tick.
    var isListVisible = false {
        didSet { if isListVisible, !oldValue { Task { await tick(forceProcesses: true) } } }
    }
    var isDashboardVisible = false {
        didSet { if isDashboardVisible, !oldValue { Task { await tick(forceProcesses: true) } } }
    }

    let reaper = ReaperEngine()
    private(set) var history = DemoData.isEnabled ? DemoData.history(now: Date()) : MetricHistory.load(from: StoragePaths.history)
    /// Biggest groups right now, ignoring the search filter.
    private(set) var topGroups: [ProcessGroup] = []
    @ObservationIgnored private var lastHistorySave = Date()
    @ObservationIgnored private var matchCache: [ProcessIdentity: String?] = [:]
    @ObservationIgnored private var matchCacheRules: [ProcessRule] = []
    @ObservationIgnored private var matchCacheProtected: [ProcessRule] = []
    /// Slop rule name per process, for badges.
    private(set) var slopMatches: [ProcessIdentity: String] = [:]

    @ObservationIgnored var onIndicatorChange: (() -> Void)?
    @ObservationIgnored private let sampler: any SnapshotSource = DemoData.isEnabled ? DemoSource() : Sampler()
    @ObservationIgnored private let controller = ProcessController()
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var lastProcessSample = Date.distantPast
    let ownPID = getpid()

    var selectedProcesses: [ProcessSample] {
        snapshot.processes.filter { selection.contains($0.id) }
    }

    // MARK: - Lifecycle

    func start() {
        guard loop == nil else { return }
        let recent = history.fine.suffix(Self.trendLength)
        cpuTrend = recent.map(\.cpu)
        memoryTrend = recent.map(\.memory)
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(for: .seconds(self.refreshInterval))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        if !DemoData.isEnabled { history.save(to: StoragePaths.history) }
    }

    private func tick(forceProcesses: Bool = false) async {
        let includeProcesses = forceProcesses || isListVisible || isDashboardVisible || Date().timeIntervalSince(lastProcessSample) >= 10
        // Ports and projects are only read while the list is on screen.
        let includeContext = isListVisible || isDashboardVisible
        let snapshot = await sampler.sample(includeProcesses: includeProcesses, includeContext: includeContext)
        if includeProcesses { lastProcessSample = snapshot.timestamp }
        apply(snapshot, processesChanged: includeProcesses)
        reaper.observe(snapshot, processesSampled: includeProcesses)
    }

    /// Runs an auto-clean sweep on the next tick.
    func sweepNow() {
        reaper.requestSweep()
        Task { await tick(forceProcesses: true) }
    }

    private func apply(_ snapshot: MonitorSnapshot, processesChanged: Bool) {
        system = snapshot.system
        cpuTrend = Array((cpuTrend + [snapshot.system.cpuUsage]).suffix(Self.trendLength))
        memoryTrend = Array((memoryTrend + [snapshot.system.memoryUsage]).suffix(Self.trendLength))
        onIndicatorChange?()
        var top: [GroupUsage]?
        if processesChanged {
            let all = ProcessGrouper().group(snapshot.processes, sortedBy: .memory)
            topGroups = Array(all.prefix(8))
            let byCPU = all.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(3)
            var seen = Set<String>()
            top = (Array(all.prefix(5)) + byCPU)
                .filter { seen.insert($0.id).inserted }
                .map { GroupUsage(name: $0.name, cpuPercent: $0.cpuPercent, memoryBytes: $0.memoryBytes) }
        }
        history.record(time: snapshot.timestamp, cpu: snapshot.system.cpuUsage, memory: snapshot.system.memoryUsage, top: top)
        if !DemoData.isEnabled, snapshot.timestamp.timeIntervalSince(lastHistorySave) >= 60 {
            lastHistorySave = snapshot.timestamp
            history.save(to: StoragePaths.history)
        }
        guard processesChanged else { return }
        self.snapshot = snapshot
        let alive = Set(snapshot.processes.map(\.id))
        selection.formIntersection(alive)
        errors = errors.filter { alive.contains($0.key) }
        regroup()
    }

    private func regroup() {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let queryBytes = Array(query.utf8)
        let portQuery = query.hasPrefix(":") ? UInt16(query.dropFirst()) : UInt16(query)
        let visible = query.isEmpty ? snapshot.processes : snapshot.processes.filter { process in
            process.matchKeys.name.contains(query)
                || String(process.pid).hasPrefix(query)
                || process.matchKeys.commandLine.contains(queryBytes)
                || portQuery.map(process.context.ports.contains) == true
                || process.context.project?.name.lowercased().contains(query) == true
        }
        groups = ProcessGrouper().group(visible, sortedBy: sortKey, mode: groupingMode)
        // A process's command line never changes, so its slop match is computed once per rule set.
        let configuration = reaper.configuration
        if configuration.rules != matchCacheRules || configuration.protected != matchCacheProtected {
            matchCache = [:]
            matchCacheRules = configuration.rules
            matchCacheProtected = configuration.protected
        }
        let policy = reaper.policy
        var matches: [ProcessIdentity: String] = [:]
        var cache: [ProcessIdentity: String?] = [:]
        for process in snapshot.processes where process.pid != ownPID {
            let match = matchCache[process.id] ?? {
                guard let rule = policy.matchingRule(for: process), !policy.isProtected(process) else { return nil }
                return rule.name
            }()
            cache[process.id] = match
            if let match { matches[process.id] = match }
        }
        matchCache = cache
        slopMatches = matches
    }

    // MARK: - Actions

    func toggleExpanded(_ group: ProcessGroup) {
        if expandedGroups.contains(group.id) { expandedGroups.remove(group.id) } else { expandedGroups.insert(group.id) }
    }

    func toggleSelection(_ process: ProcessSample) {
        if selection.contains(process.id) { selection.remove(process.id) } else { selection.insert(process.id) }
    }

    func isQuittable(_ process: ProcessSample) -> Bool { process.pid != ownPID && !DemoData.isEnabled }

    func quit(_ process: ProcessSample) {
        quit([process])
    }

    func quit(_ group: ProcessGroup) {
        quit(group.processes)
    }

    func quitSelection() {
        quit(selectedProcesses)
        selection.removeAll()
    }

    private func quit(_ processes: [ProcessSample]) {
        let targets = processes.filter { isQuittable($0) && !quitting.contains($0.id) }
        guard !targets.isEmpty else { return }
        quitting.formUnion(targets.map(\.id))
        for target in targets { errors[target.id] = nil }
        Task {
            let outcomes = await controller.quit(targets)
            var closed: [ProcessSample] = []
            for (identity, outcome) in outcomes {
                quitting.remove(identity)
                if let message = outcome.errorMessage { errors[identity] = message }
                if outcome.errorMessage == nil, let target = targets.first(where: { $0.id == identity }) { closed.append(target) }
            }
            reaper.recordManual(closed)
            await tick(forceProcesses: true)
        }
    }
}

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

    /// True while a view lists processes; the process table is then refreshed every tick.
    var isListVisible = false {
        didSet { if isListVisible, !oldValue { Task { await tick(forceProcesses: true) } } }
    }

    @ObservationIgnored var onIndicatorChange: (() -> Void)?
    @ObservationIgnored private let sampler = Sampler()
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
    }

    private func tick(forceProcesses: Bool = false) async {
        let includeProcesses = forceProcesses || isListVisible || Date().timeIntervalSince(lastProcessSample) >= 10
        let snapshot = await sampler.sample(includeProcesses: includeProcesses)
        if includeProcesses { lastProcessSample = snapshot.timestamp }
        apply(snapshot, processesChanged: includeProcesses)
    }

    private func apply(_ snapshot: MonitorSnapshot, processesChanged: Bool) {
        system = snapshot.system
        cpuTrend = Array((cpuTrend + [snapshot.system.cpuUsage]).suffix(Self.trendLength))
        memoryTrend = Array((memoryTrend + [snapshot.system.memoryUsage]).suffix(Self.trendLength))
        onIndicatorChange?()
        guard processesChanged else { return }
        self.snapshot = snapshot
        let alive = Set(snapshot.processes.map(\.id))
        selection.formIntersection(alive)
        errors = errors.filter { alive.contains($0.key) }
        regroup()
    }

    private func regroup() {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let visible = query.isEmpty ? snapshot.processes : snapshot.processes.filter { process in
            process.name.lowercased().contains(query)
                || String(process.pid).hasPrefix(query)
                || process.commandLine.lowercased().contains(query)
        }
        groups = ProcessGrouper().group(visible, sortedBy: sortKey)
    }

    // MARK: - Actions

    func toggleExpanded(_ group: ProcessGroup) {
        if expandedGroups.contains(group.id) { expandedGroups.remove(group.id) } else { expandedGroups.insert(group.id) }
    }

    func toggleSelection(_ process: ProcessSample) {
        if selection.contains(process.id) { selection.remove(process.id) } else { selection.insert(process.id) }
    }

    func isQuittable(_ process: ProcessSample) -> Bool { process.pid != ownPID }

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
            for (identity, outcome) in outcomes {
                quitting.remove(identity)
                if let message = outcome.errorMessage { errors[identity] = message }
            }
            await tick(forceProcesses: true)
        }
    }
}

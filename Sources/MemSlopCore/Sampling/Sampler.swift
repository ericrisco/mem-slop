import Foundation

/// Produces `MonitorSnapshot`s off the main thread.
///
/// System totals are cheap and sampled every tick; the process table is heavier, so callers
/// can skip it and reuse the last one while nobody is looking at the list.
public actor Sampler {
    private let system = SystemSampler()
    private let processes = ProcessSampler()
    private var lastProcesses: [ProcessSample] = []
    private var lastTree: [Int32: ProcessNode] = [:]

    public init() {}

    public func sample(includeProcesses: Bool = true, includeContext: Bool = false) -> MonitorSnapshot {
        let system = system.sample()
        if includeProcesses || lastTree.isEmpty {
            (lastProcesses, lastTree) = processes.sample(includeContext: includeContext)
        }
        return MonitorSnapshot(timestamp: Date(), system: system, processes: lastProcesses, tree: lastTree)
    }
}

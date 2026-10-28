import Foundation

/// Anything that can produce monitor snapshots: the real sampler, or demo data.
public protocol SnapshotSource: Actor {
    func sample(includeProcesses: Bool, includeContext: Bool) -> MonitorSnapshot
}

extension Sampler: SnapshotSource {}

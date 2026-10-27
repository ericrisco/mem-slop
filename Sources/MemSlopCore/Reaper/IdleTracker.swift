import Foundation

/// Remembers coarse CPU-time and memory checkpoints per process to tell whether it has been idle.
public struct IdleTracker: Sendable {
    public struct Checkpoint: Sendable, Equatable {
        public let time: Date
        public let cpuTimeNanos: UInt64
        public let memoryBytes: UInt64
    }

    public struct Activity: Sendable, Equatable {
        /// Average CPU over the window, Activity Monitor scale (100 = one core).
        public let averageCPU: Double
        /// Largest minus smallest footprint seen in the window.
        public let memoryChange: UInt64
        public let peakMemory: UInt64
        /// How long the process has been observed without gaps.
        public let observedFor: TimeInterval
    }

    public var checkpointInterval: TimeInterval
    /// A longer silence (sleep, app paused) resets the history: we cannot vouch for that time.
    public var maxGap: TimeInterval
    public var retention: TimeInterval
    private(set) var history: [ProcessIdentity: [Checkpoint]] = [:]

    public init(checkpointInterval: TimeInterval = 30, maxGap: TimeInterval = 120, retention: TimeInterval = 65 * 60) {
        self.checkpointInterval = checkpointInterval
        self.maxGap = maxGap
        self.retention = retention
    }

    public mutating func record(_ processes: [ProcessSample], at now: Date) {
        var alive = Set<ProcessIdentity>()
        for process in processes {
            alive.insert(process.id)
            let checkpoint = Checkpoint(time: now, cpuTimeNanos: process.cpuTimeNanos, memoryBytes: process.memoryBytes)
            var points = history[process.id] ?? []
            if let last = points.last {
                if now.timeIntervalSince(last.time) > maxGap {
                    points = [checkpoint]
                } else if now.timeIntervalSince(last.time) >= checkpointInterval {
                    points.append(checkpoint)
                }
            } else {
                points = [checkpoint]
            }
            if let first = points.first, now.timeIntervalSince(first.time) > retention {
                points.removeAll { now.timeIntervalSince($0.time) > retention }
            }
            history[process.id] = points
        }
        history = history.filter { alive.contains($0.key) }
    }

    /// Activity over the last `window`, or `nil` if the process was not observed for the whole window.
    public func activity(of process: ProcessSample, over window: TimeInterval, now: Date) -> Activity? {
        guard let points = history[process.id], let first = points.first else { return nil }
        let observedFor = now.timeIntervalSince(first.time)
        guard observedFor >= window, let start = points.last(where: { now.timeIntervalSince($0.time) >= window }) else {
            return nil
        }
        let elapsed = now.timeIntervalSince(start.time)
        guard elapsed > 0 else { return nil }
        let cpuDelta = process.cpuTimeNanos >= start.cpuTimeNanos ? process.cpuTimeNanos - start.cpuTimeNanos : 0
        let averageCPU = Double(cpuDelta) / (elapsed * 1_000_000_000) * 100
        let memories = points.filter { $0.time >= start.time }.map(\.memoryBytes) + [process.memoryBytes]
        let peak = memories.max() ?? process.memoryBytes
        let low = memories.min() ?? process.memoryBytes
        return Activity(averageCPU: averageCPU, memoryChange: peak - low, peakMemory: peak, observedFor: observedFor)
    }
}

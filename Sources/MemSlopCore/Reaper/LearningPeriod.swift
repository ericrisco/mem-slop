import Foundation

/// The first day after install: auto-clean only records what it would close, then asks.
public struct LearningPeriod: Codable, Sendable, Equatable {
    public enum Phase: Equatable, Sendable {
        /// Still watching; every close is a dry run.
        case learning(remaining: TimeInterval)
        /// The day is over and the user has not decided yet; still a dry run.
        case awaitingDecision
        /// The user decided (or this install predates learning mode).
        case done
    }

    public static let duration: TimeInterval = 24 * 3600

    public private(set) var started: Date
    public private(set) var decided = false
    /// Memory of each distinct process that would have been closed, keyed by its identity.
    public private(set) var wouldClose: [String: UInt64] = [:]
    public var announced = false

    public init(started: Date, decided: Bool = false) {
        self.started = started
        self.decided = decided
    }

    /// An install that already had settings before learning mode existed.
    public static func skipped(at date: Date) -> LearningPeriod {
        LearningPeriod(started: date, decided: true)
    }

    public func phase(at now: Date) -> Phase {
        if decided { return .done }
        let elapsed = now.timeIntervalSince(started)
        return elapsed < Self.duration ? .learning(remaining: Self.duration - elapsed) : .awaitingDecision
    }

    /// True while auto-clean must not close anything.
    public func forcesDryRun(at now: Date) -> Bool { phase(at: now) != .done }

    /// Records processes a dry-run sweep would have closed; the same process is counted once.
    public mutating func record(_ entries: [ActivityEntry]) {
        for entry in entries where entry.outcome == .wouldQuit {
            wouldClose["\(entry.pid):\(entry.name)"] = entry.memoryBytes
        }
    }

    public var processCount: Int { wouldClose.count }
    public var memoryBytes: UInt64 { wouldClose.values.reduce(0, +) }

    public mutating func decide() {
        decided = true
    }

    public mutating func endNow(at now: Date) {
        started = now.addingTimeInterval(-Self.duration)
    }
}

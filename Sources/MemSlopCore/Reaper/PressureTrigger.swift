import Foundation

/// Decides when sustained critical memory pressure warrants an early sweep.
public struct PressureTrigger: Sendable {
    public var delay: TimeInterval
    public var cooldown: TimeInterval
    private(set) var criticalSince: Date?
    private(set) var lastFired: Date?

    public init(delay: TimeInterval = ReaperConfiguration.pressureDelay, cooldown: TimeInterval = ReaperConfiguration.pressureCooldown) {
        self.delay = delay
        self.cooldown = cooldown
    }

    /// Feed every sample; returns true once pressure has been critical for `delay`, at most once per `cooldown`.
    public mutating func observe(_ pressure: MemoryPressure, at now: Date) -> Bool {
        guard pressure == .critical else {
            criticalSince = nil
            return false
        }
        let since = criticalSince ?? now
        criticalSince = since
        guard now.timeIntervalSince(since) >= delay else { return false }
        if let lastFired, now.timeIntervalSince(lastFired) < cooldown { return false }
        lastFired = now
        return true
    }
}

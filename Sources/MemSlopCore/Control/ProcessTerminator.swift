import Darwin
import Foundation

public enum TerminationResult: String, Sendable, Codable {
    /// Exited after SIGTERM.
    case terminated
    /// Needed SIGKILL.
    case killed
    /// Was already gone.
    case notRunning
    /// Not allowed (not owned by the user).
    case permissionDenied
    case failed

    public var succeeded: Bool { self == .terminated || self == .killed || self == .notRunning }
}

/// Quits processes gracefully, escalating to SIGKILL when they do not exit in time.
public struct ProcessTerminator: Sendable {
    public var gracePeriod: Duration

    public init(gracePeriod: Duration = .seconds(5)) {
        self.gracePeriod = gracePeriod
    }

    /// Sends SIGTERM, waits up to `gracePeriod`, then SIGKILL.
    public func terminate(_ identity: ProcessIdentity) async -> TerminationResult {
        guard Self.isAlive(identity) else { return .notRunning }
        if kill(identity.pid, SIGTERM) != 0 {
            return errno == EPERM ? .permissionDenied : (errno == ESRCH ? .notRunning : .failed)
        }
        if await waitForExit(identity, timeout: gracePeriod) { return .terminated }
        guard Self.isAlive(identity) else { return .terminated }
        if kill(identity.pid, SIGKILL) != 0 {
            return errno == ESRCH ? .terminated : .failed
        }
        return await waitForExit(identity, timeout: .seconds(2)) ? .killed : .failed
    }

    /// Terminates many processes concurrently.
    public func terminate(_ identities: [ProcessIdentity]) async -> [ProcessIdentity: TerminationResult] {
        await withTaskGroup(of: (ProcessIdentity, TerminationResult).self) { group in
            for identity in identities {
                group.addTask { (identity, await terminate(identity)) }
            }
            var results: [ProcessIdentity: TerminationResult] = [:]
            for await (identity, result) in group { results[identity] = result }
            return results
        }
    }

    private func waitForExit(_ identity: ProcessIdentity, timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if !Self.isAlive(identity) { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return !Self.isAlive(identity)
    }

    /// True when the same process (PID and start time) is still running and not a zombie.
    public static func isAlive(_ identity: ProcessIdentity) -> Bool {
        guard let entry = ProcessSampler.kernelProcess(identity.pid) else { return false }
        return entry.startTime == identity.startTime && !entry.isZombie
    }

    /// Identity of a running PID, if any.
    public static func identity(of pid: Int32) -> ProcessIdentity? {
        ProcessSampler.kernelProcess(pid)?.identity
    }
}

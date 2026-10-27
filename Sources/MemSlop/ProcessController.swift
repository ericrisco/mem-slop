import AppKit
import MemSlopCore

/// Quits processes the way a user expects: real apps are asked to quit like the Dock does
/// (and never force-killed, they may be asking to save); everything else gets SIGTERM → SIGKILL.
@MainActor
final class ProcessController {
    enum Outcome {
        case done(TerminationResult)
        case appStillRunning

        var errorMessage: String? {
            switch self {
            case .appStillRunning: "Still running — it may be asking to save"
            case .done(.permissionDenied): "Not allowed (owned by another user)"
            case .done(.failed): "Could not quit"
            case .done: nil
            }
        }
    }

    private let terminator = ProcessTerminator()

    func quit(_ processes: [ProcessSample]) async -> [ProcessIdentity: Outcome] {
        let groupedPIDs = Set(processes.map(\.pid))
        var apps: [(ProcessSample, NSRunningApplication)] = []
        var others: [ProcessSample] = []
        for process in processes {
            if let app = NSRunningApplication(processIdentifier: process.pid), app.activationPolicy != .prohibited {
                apps.append((process, app))
            } else if groupedPIDs.contains(process.ppid),
                      NSRunningApplication(processIdentifier: process.ppid) != nil {
                // A helper whose app is quitting too: it will go away with its parent.
                continue
            } else {
                others.append(process)
            }
        }

        var outcomes: [ProcessIdentity: Outcome] = [:]
        for (process, app) in apps {
            app.terminate()
            outcomes[process.id] = await waitForApp(app) ? .done(.terminated) : .appStillRunning
        }
        let results = await terminator.terminate(others.map(\.id))
        for (identity, result) in results { outcomes[identity] = .done(result) }
        for process in processes where outcomes[process.id] == nil { outcomes[process.id] = .done(.terminated) }
        return outcomes
    }

    private func waitForApp(_ app: NSRunningApplication) async -> Bool {
        for _ in 0..<50 {
            if app.isTerminated { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return app.isTerminated
    }
}

import Foundation

/// A process left running by an agent session that has ended.
public struct SessionLeftover: Hashable, Sendable {
    public let identity: ProcessIdentity
    /// "Claude Code", "Codex"…
    public let agent: String
    public let endedAt: Date

    public init(identity: ProcessIdentity, agent: String, endedAt: Date) {
        self.identity = identity
        self.agent = agent
        self.endedAt = endedAt
    }

    public var reason: String { "\(agent) session ended" }
}

/// Watches agent processes and reports what each one leaves behind when it exits.
/// Works for any agent CLI, with no hook installed.
public struct AgentSessionTracker: Sendable {
    private struct Session {
        let agent: String
        var processes: Set<ProcessIdentity>
    }

    private var sessions: [ProcessIdentity: Session] = [:]

    public init() {}

    /// Records which agent each process descends from; returns leftovers of agents that are gone.
    public mutating func observe(_ snapshot: MonitorSnapshot) -> [SessionLeftover] {
        let byPID = Dictionary(snapshot.processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var agents: [Int32: String] = [:]
        for process in snapshot.processes {
            let node = ProcessNode(pid: process.pid, ppid: process.ppid, name: process.name, executablePath: process.executablePath)
            if let agent = AncestryClassifier.agentName(node, arguments: process.arguments) { agents[process.pid] = agent }
        }

        for process in snapshot.processes where agents[process.pid] == nil {
            guard let agentPID = Self.nearestAgent(of: process, tree: snapshot.tree, agents: agents),
                  let agentProcess = byPID[agentPID] else { continue }
            sessions[agentProcess.id, default: Session(agent: agents[agentPID] ?? "Agent", processes: [])].processes.insert(process.id)
        }

        let alive = Set(snapshot.processes.map(\.id))
        var leftovers: [SessionLeftover] = []
        for (agent, session) in sessions where !alive.contains(agent) {
            for identity in session.processes where alive.contains(identity) {
                leftovers.append(SessionLeftover(identity: identity, agent: session.agent, endedAt: snapshot.timestamp))
            }
            sessions[agent] = nil
        }
        // Forget processes that exited while their agent lives on.
        for key in sessions.keys { sessions[key]?.processes.formIntersection(alive) }
        return leftovers
    }

    static func nearestAgent(of process: ProcessSample, tree: [Int32: ProcessNode], agents: [Int32: String]) -> Int32? {
        var pid = process.ppid
        var visited: Set<Int32> = [process.pid]
        while pid > 1, !visited.contains(pid), let node = tree[pid] {
            if agents[pid] != nil { return pid }
            visited.insert(pid)
            pid = node.ppid
        }
        return nil
    }

    /// What a session-end hook should report: everything below the agent (minus the hook itself)
    /// plus every process tagged with the session ID, which finds servers re-parented to launchd.
    public static func leftovers(
        agentPID: Int32?, sessionID: String?, excluding chain: Set<Int32>, in snapshot: MonitorSnapshot
    ) -> [ProcessIdentity] {
        var children: [Int32: [Int32]] = [:]
        for node in snapshot.tree.values { children[node.ppid, default: []].append(node.pid) }
        var pids = Set<Int32>()
        if let agentPID {
            var queue = children[agentPID] ?? []
            while let pid = queue.popLast() {
                guard !chain.contains(pid), pids.insert(pid).inserted else { continue }
                queue.append(contentsOf: children[pid] ?? [])
            }
        }
        return snapshot.processes
            .filter { process in
                guard !chain.contains(process.pid), process.pid != agentPID else { return false }
                if pids.contains(process.pid) { return true }
                if let sessionID, process.agentSessionID == sessionID { return true }
                return false
            }
            .map(\.id)
    }
}

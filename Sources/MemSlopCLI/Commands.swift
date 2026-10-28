import Darwin
import Foundation
import MemSlopCore

enum Commands {
    static let usage = """
    memslop — see and clean up the dev slop your AI agents leave running.

    USAGE
      memslop status                       CPU, memory, pressure and slop at a glance
      memslop ps [--slop] [--json]         processes grouped by project, with ports
      memslop ports [--json]               everything listening on a TCP port
      memslop quit <pid|:port>... [--yes]  quit processes (SIGTERM, then SIGKILL)
      memslop hooks install [--claude] [--codex]
                                           clean up when an agent session ends
      memslop hooks uninstall|status [--claude] [--codex]
      memslop --version

    Closes are logged in MemSlop's activity log and count towards memory freed.
    """

    // MARK: - Snapshot

    struct Reading {
        let system: SystemSnapshot
        let snapshot: MonitorSnapshot
        let policy: ReaperPolicy

        func slopRule(_ process: ProcessSample) -> String? {
            guard let rule = policy.matchingRule(for: process), !policy.isProtected(process) else { return nil }
            return rule.name
        }
    }

    /// Two samples 0.4 s apart: CPU percentages are measured between them.
    static func read() -> Reading {
        let systemSampler = SystemSampler()
        let processSampler = ProcessSampler()
        _ = systemSampler.sample()
        _ = processSampler.sample()
        usleep(400_000)
        let system = systemSampler.sample()
        let (processes, tree) = processSampler.sample(includeContext: true)
        let own = getpid()
        let snapshot = MonitorSnapshot(timestamp: Date(), system: system, processes: processes.filter { $0.pid != own }, tree: tree)
        return Reading(system: system, snapshot: snapshot, policy: ReaperPolicy(configuration: .saved()))
    }

    // MARK: - status

    static func status(_ arguments: [String]) throws {
        let reading = read()
        let system = reading.system
        let slop = reading.snapshot.processes.filter { reading.slopRule($0) != nil }
        let slopMemory = slop.reduce(UInt64(0)) { $0 + $1.memoryBytes }
        let pressure: String = switch system.pressure {
        case .normal: Terminal.green("normal")
        case .warning: Terminal.orange("warning")
        case .critical: Terminal.red("critical")
        }
        print("\(Terminal.bold("CPU")) \(Formatting.percent(system.cpuUsage))   \(Terminal.bold("Memory")) \(Formatting.percent(system.memoryUsage)) (\(Formatting.bytes(system.memoryUsed)) of \(Formatting.bytes(system.memoryTotal)))   \(Terminal.bold("Pressure")) \(pressure)   \(Terminal.bold("Swap")) \(Formatting.bytes(system.swapUsed))")
        print("\(Terminal.orange("\(slop.count) slop")) processes using \(Formatting.bytes(slopMemory))\(slop.isEmpty ? "" : " — see them with `memslop ps --slop`")")
    }

    // MARK: - ps

    struct ProcessRecord: Encodable {
        let pid: Int32
        let name: String
        let cpuPercent: Double
        let memoryBytes: UInt64
        let ports: [UInt16]
        let project: String?
        let workingDirectory: String?
        let slopRule: String?
        let command: String
    }

    static func record(_ process: ProcessSample, _ reading: Reading) -> ProcessRecord {
        ProcessRecord(
            pid: process.pid, name: process.name, cpuPercent: (process.cpuPercent * 10).rounded() / 10,
            memoryBytes: process.memoryBytes, ports: process.context.ports, project: process.context.project?.path,
            workingDirectory: process.context.workingDirectory, slopRule: reading.slopRule(process), command: process.commandLine
        )
    }

    static func ps(_ arguments: [String]) throws {
        let reading = read()
        var processes = reading.snapshot.processes
        if arguments.contains("--slop") { processes = processes.filter { reading.slopRule($0) != nil } }
        if arguments.contains("--json") {
            try Terminal.json(processes.sorted { $0.memoryBytes > $1.memoryBytes }.map { record($0, reading) })
            return
        }
        let groups = ProcessGrouper().group(processes, sortedBy: .memory, mode: .project)
        let limit = arguments.contains("--all") ? Int.max : 25
        for group in groups.prefix(limit) {
            let ports = group.ports.isEmpty ? "" : "  " + Terminal.blue(group.ports.map { ":\($0)" }.joined(separator: " "))
            print("\(Terminal.bold(group.name))  \(Terminal.dim("\(group.processes.count) · \(Formatting.bytes(group.memoryBytes)) · \(Formatting.cpu(group.cpuPercent))"))\(ports)")
            for process in group.processes.prefix(8) {
                let slop = reading.slopRule(process).map { "  " + Terminal.orange("slop: \($0)") } ?? ""
                let processPorts = process.context.ports.isEmpty ? "" : " " + Terminal.blue(process.context.ports.map { ":\($0)" }.joined(separator: " "))
                print("  \(Terminal.cell(String(process.pid), 7, right: true))  \(Terminal.cell(Formatting.bytes(process.memoryBytes), 8, right: true))  \(Terminal.cell(Formatting.cpu(process.cpuPercent), 6, right: true))  \(Terminal.cell(process.name, 24))\(processPorts)\(slop)")
            }
            if group.processes.count > 8 { print(Terminal.dim("  … \(group.processes.count - 8) more")) }
        }
        if groups.count > limit { print(Terminal.dim("… \(groups.count - limit) more groups (use --all)")) }
    }

    // MARK: - ports

    static func ports(_ arguments: [String]) throws {
        let reading = read()
        let listening = reading.snapshot.processes.filter { !$0.context.ports.isEmpty }
        let rows = listening.flatMap { process in process.context.ports.map { ($0, process) } }.sorted { $0.0 < $1.0 }
        if arguments.contains("--json") {
            struct PortRecord: Encodable { let port: UInt16; let process: ProcessRecord }
            try Terminal.json(rows.map { PortRecord(port: $0.0, process: record($0.1, reading)) })
            return
        }
        guard !rows.isEmpty else { print("Nothing of yours is listening on a TCP port."); return }
        print(Terminal.dim("\(Terminal.cell("PORT", 7))\(Terminal.cell("PID", 8))\(Terminal.cell("NAME", 22))\(Terminal.cell("PROJECT", 22))\(Terminal.cell("MEMORY", 9, right: true))  SLOP"))
        for (port, process) in rows {
            let slop = reading.slopRule(process).map { Terminal.orange($0) } ?? ""
            print("\(Terminal.blue(Terminal.cell(":\(port)", 7)))\(Terminal.cell(String(process.pid), 8))\(Terminal.cell(process.name, 22))\(Terminal.cell(process.context.project?.name ?? "–", 22))\(Terminal.cell(Formatting.bytes(process.memoryBytes), 9, right: true))  \(slop)")
        }
    }

    // MARK: - quit

    static func quit(_ arguments: [String]) async throws -> Int32 {
        let yes = arguments.contains("--yes") || arguments.contains("-y")
        let targets = arguments.filter { !$0.hasPrefix("-") }
        guard !targets.isEmpty else {
            Terminal.error("say what to quit: a PID or a :port, e.g. `memslop quit :3000`")
            return 64
        }
        let reading = read()
        let appPIDs = Set(reading.snapshot.processes.filter { $0.executablePath.hasSuffix("/MemSlop.app/Contents/MacOS/MemSlop") }.map(\.pid))
        var chosen: [ProcessSample] = []
        for target in targets {
            let matches: [ProcessSample]
            if target.hasPrefix(":"), let port = UInt16(target.dropFirst()) {
                matches = reading.snapshot.processes.filter { $0.context.ports.contains(port) }
            } else if let pid = Int32(target) {
                matches = reading.snapshot.processes.filter { $0.pid == pid }
            } else {
                Terminal.error("'\(target)' is not a PID or a :port")
                return 64
            }
            if matches.isEmpty {
                Terminal.error("nothing of yours matches \(target)")
                return 1
            }
            chosen += matches.filter { !appPIDs.contains($0.pid) && !chosen.contains($0) }
        }
        guard !chosen.isEmpty else { return 0 }
        let total = chosen.reduce(UInt64(0)) { $0 + $1.memoryBytes }
        for process in chosen {
            print("  \(Terminal.cell(String(process.pid), 7, right: true))  \(Terminal.cell(Formatting.bytes(process.memoryBytes), 8, right: true))  \(process.name)  \(Terminal.dim(process.commandLine))")
        }
        if !yes {
            guard Terminal.isInteractive else {
                Terminal.error("not a terminal: pass --yes to quit without asking")
                return 2
            }
            guard Terminal.confirm("Quit \(chosen.count) process\(chosen.count == 1 ? "" : "es") (\(Formatting.bytes(total)))?") else {
                print("Nothing was closed.")
                return 1
            }
        }
        let results = await ProcessTerminator().terminate(chosen.map(\.id))
        var entries: [ActivityEntry] = []
        var failed = 0
        for process in chosen {
            let result = results[process.id] ?? .failed
            let outcome: ActivityEntry.Outcome = switch result {
            case .terminated, .notRunning: .quit
            case .killed: .forced
            case .permissionDenied, .failed: .failed
            }
            if outcome == .failed { failed += 1 }
            entries.append(ActivityEntry(
                date: Date(), name: process.name, pid: process.pid, group: ProcessGrouper.classify(process).name,
                rule: "Manual", reason: "quit from the terminal", memoryBytes: process.memoryBytes,
                commandLine: process.commandLine, outcome: outcome
            ))
        }
        _ = try? Inbox().post(InboxEvent(kind: .activity, activity: entries))
        let freed = entries.filter { $0.outcome.freedMemory }.reduce(UInt64(0)) { $0 + $1.memoryBytes }
        print("\(Terminal.green("Closed \(chosen.count - failed)")) · freed \(Formatting.bytes(freed))\(failed > 0 ? " · " + Terminal.red("\(failed) failed") : "")")
        return failed > 0 ? 1 : 0
    }

    // MARK: - hooks

    static func hooks(_ arguments: [String]) throws -> Int32 {
        guard let action = arguments.first, ["install", "uninstall", "status"].contains(action) else {
            Terminal.error("use `memslop hooks install|uninstall|status [--claude] [--codex]`")
            return 64
        }
        var agents = AgentKind.allCases.filter { arguments.contains("--\($0.rawValue)") }
        let explicit = !agents.isEmpty
        if agents.isEmpty { agents = AgentKind.allCases }
        let executable = Executable.resolvedURL.path
        for agent in agents {
            let installer = HookInstaller(agent: agent, executable: executable)
            let status = installer.status()
            switch action {
            case "install":
                if status == .agentMissing, !explicit {
                    print("\(agent.displayName): not set up on this Mac, skipped")
                    continue
                }
                let changed = try installer.install()
                print("\(agent.displayName): \(changed ? Terminal.green("connected") : "already connected") (\(installer.file.path))")
            case "uninstall":
                let changed = try installer.uninstall()
                print("\(agent.displayName): \(changed ? "disconnected" : "was not connected")")
            default:
                let label: String = switch status {
                case .installed: Terminal.green("connected")
                case .notInstalled: "not connected"
                case .agentMissing: Terminal.dim("not set up on this Mac")
                }
                print("\(agent.displayName): \(label)")
            }
        }
        return 0
    }

    /// Run by the agent's SessionEnd hook. Must be quick and must never fail the agent.
    static func hook(_ arguments: [String]) {
        guard arguments.first == "session-end" else { return }
        let agentFlag = arguments.firstIndex(of: "--agent").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        let agent = AgentKind(rawValue: agentFlag ?? "") ?? .claude
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let payload = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any]
        let sessionID = payload?["session_id"] as? String
        // `/clear` and `/resume` end a session but the agent keeps running with the same tools.
        if let reason = payload?["reason"] as? String, HookPayload.continuingReasons.contains(reason) { return }

        let (processes, tree) = ProcessSampler().sample()
        let snapshot = MonitorSnapshot(timestamp: Date(), system: SystemSnapshot(), processes: processes, tree: tree)
        let arguments = Dictionary(processes.map { ($0.pid, $0.arguments) }, uniquingKeysWith: { first, _ in first })
        // Walk up from this hook to the agent; everything on the way is the hook's own plumbing.
        var chain: Set<Int32> = [getpid()]
        var agentPID: Int32?
        var pid = getppid()
        while pid > 1, let node = tree[pid], !chain.contains(pid) {
            if AncestryClassifier.agentName(node, arguments: arguments[pid] ?? []) != nil {
                agentPID = pid
                break
            }
            chain.insert(pid)
            pid = node.ppid
        }
        let leftovers = AgentSessionTracker.leftovers(agentPID: agentPID, sessionID: sessionID, excluding: chain, in: snapshot)
        let event = InboxEvent(kind: .sessionEnded, agent: agent.displayName, sessionID: sessionID, processes: leftovers)
        _ = try? Inbox().post(event)
    }
}

enum HookPayload {
    /// SessionEnd reasons after which the agent process carries on.
    static let continuingReasons: Set<String> = ["clear", "resume", "compact"]
}

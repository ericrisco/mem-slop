import Foundation
import Testing
@testable import MemSlopCore

@Suite struct ProcArgsEnvironmentTests {
    @Test func readsArgumentsThenEnvironment() {
        var buffer: [UInt8] = []
        withUnsafeBytes(of: Int32(2)) { buffer += $0 }
        buffer += Array("/usr/bin/node".utf8) + [0, 0, 0]
        for string in ["node", "server.js", "PATH=/usr/bin", "CLAUDE_CODE_SESSION_ID=abc-123"] {
            buffer += Array(string.utf8) + [0]
        }
        buffer += [0, 0]
        let parsed = ProcessSampler.parseProcArgsAndEnvironment(buffer)
        #expect(parsed.arguments == ["node", "server.js"])
        #expect(parsed.environment == ["PATH=/usr/bin", "CLAUDE_CODE_SESSION_ID=abc-123"])
        #expect(ProcessSampler.value(of: ProcessSampler.sessionVariable, in: parsed.environment) == "abc-123")
        #expect(ProcessSampler.value(of: "HOME", in: parsed.environment) == nil)
    }

    @Test func livePickUpOfSessionTag() async throws {
        // macOS hides the environment of Apple platform binaries such as /bin/sleep; a freshly
        // compiled program behaves like the node or python of a dev server.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("env-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("devserver.c")
        let binary = directory.appendingPathComponent("devserver")
        try Data("#include <unistd.h>\nint main(void) { sleep(30); return 0; }\n".utf8).write(to: source)
        let compile = Process()
        compile.executableURL = URL(fileURLWithPath: "/usr/bin/cc")
        compile.arguments = [source.path, "-o", binary.path]
        try compile.run()
        compile.waitUntilExit()
        try #require(compile.terminationStatus == 0)

        let process = Process()
        process.executableURL = binary
        process.arguments = ["30"]
        process.environment = ["CLAUDE_CODE_SESSION_ID": "live-session"]
        try process.run()
        defer { process.terminate() }
        try await Task.sleep(for: .milliseconds(200))
        let sample = ProcessSampler().sample().processes.first { $0.pid == process.processIdentifier }
        #expect(sample?.agentSessionID == "live-session")
    }
}

@Suite struct AgentSessionTrackerTests {
    private func snapshot(_ processes: [ProcessSample], at time: TimeInterval = 0) -> MonitorSnapshot {
        var tree: [Int32: ProcessNode] = [:]
        for process in processes {
            tree[process.pid] = ProcessNode(pid: process.pid, ppid: process.ppid, name: process.name, executablePath: process.executablePath)
        }
        return MonitorSnapshot(timestamp: Date(timeIntervalSince1970: time), system: SystemSnapshot(), processes: processes, tree: tree)
    }

    @Test func reportsWhatAnExitedAgentLeftBehind() {
        let shell = Fixture.process(pid: 10, name: "zsh")
        let agent = Fixture.process(pid: 20, ppid: 10, name: "codex", path: "/opt/homebrew/bin/codex")
        let server = Fixture.process(pid: 30, ppid: 20, name: "python3", arguments: ["python3", "-m", "http.server"])
        let other = Fixture.process(pid: 40, ppid: 10, name: "vim")
        var tracker = AgentSessionTracker()
        #expect(tracker.observe(snapshot([shell, agent, server, other])).isEmpty)

        // Codex exits; its server is re-parented to launchd.
        let orphan = Fixture.process(pid: 30, ppid: 1, name: "python3", arguments: ["python3", "-m", "http.server"])
        let leftovers = tracker.observe(snapshot([shell, orphan, other], at: 60))
        #expect(leftovers.map(\.identity) == [server.id])
        #expect(leftovers.first?.agent == "Codex")
        #expect(leftovers.first?.reason == "Codex session ended")
        // Reported once.
        #expect(tracker.observe(snapshot([shell, orphan, other], at: 90)).isEmpty)
    }

    @Test func hookFindsDescendantsAndTaggedOrphans() {
        let agent = Fixture.process(pid: 20, ppid: 10, name: "claude")
        let shell = Fixture.process(pid: 21, ppid: 20, name: "zsh")
        let hook = Fixture.process(pid: 22, ppid: 21, name: "memslop")
        let mcp = Fixture.process(pid: 23, ppid: 20, name: "node")
        var detached = Fixture.process(pid: 30, ppid: 1, name: "node", arguments: ["node", "next", "dev"])
        detached.agentSessionID = "s1"
        var otherSession = Fixture.process(pid: 31, ppid: 1, name: "node")
        otherSession.agentSessionID = "s2"
        let snapshot = snapshot([agent, shell, hook, mcp, detached, otherSession])

        let found = Set(AgentSessionTracker.leftovers(agentPID: 20, sessionID: "s1", excluding: [21, 22], in: snapshot))
        #expect(found == [mcp.id, detached.id])
    }
}

@Suite struct LeftoverPolicyTests {
    @Test func leftoversNeedNoRuleButKeepEverySafeguard() {
        var configuration = ReaperConfiguration()
        configuration.intervalMinutes = 10
        let policy = ReaperPolicy(configuration: configuration)
        let start = Date(timeIntervalSince1970: 0)
        let unknown = Fixture.process(pid: 50, name: "my-tool", memoryMB: 200)
        let protectedApp = Fixture.process(pid: 51, name: "Slack", path: "/Applications/Slack.app/Contents/MacOS/Slack")
        let agent = Fixture.process(pid: 52, name: "claude")
        let busy = Fixture.process(pid: 53, name: "worker")

        var tracker = IdleTracker()
        let busyLater = Fixture.process(pid: 53, name: "worker", cpuTimeNanos: 200_000_000_000)
        for second in stride(from: 0, through: 330, by: 30) {
            tracker.record([unknown, protectedApp, agent, second == 330 ? busyLater : busy], at: start + TimeInterval(second))
        }
        let now = start + 330
        var tree: [Int32: ProcessNode] = [:]
        for process in [unknown, protectedApp, agent, busyLater] {
            tree[process.pid] = ProcessNode(pid: process.pid, ppid: 1, name: process.name, executablePath: process.executablePath)
        }
        let snapshot = MonitorSnapshot(timestamp: now, system: SystemSnapshot(), processes: [unknown, protectedApp, agent, busyLater], tree: tree)
        let leftovers = Dictionary(uniqueKeysWithValues: [unknown, protectedApp, agent, busyLater].map {
            ($0.id, SessionLeftover(identity: $0.id, agent: "Claude Code", endedAt: start))
        })

        #expect(policy.matchingRule(for: unknown) == nil)
        let candidates = policy.leftoverCandidates(
            in: snapshot, leftovers: leftovers, tracker: tracker, regularAppPIDs: [], kept: [],
            window: configuration.leftoverWindow, now: now
        )
        #expect(candidates.map(\.id) == [unknown.id])
        #expect(candidates.first?.rule == "Session leftover")

        let notYet = policy.leftoverCandidates(
            in: snapshot, leftovers: leftovers, tracker: tracker, regularAppPIDs: [], kept: [unknown.id],
            window: configuration.leftoverWindow, now: now
        )
        #expect(notYet.isEmpty)
    }
}

@Suite struct InboxTests {
    @Test func postAndDrainInOrder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("inbox-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = Inbox(directory: directory)
        #expect(!inbox.hasPending)
        try inbox.post(InboxEvent(kind: .sessionEnded, date: Date(timeIntervalSince1970: 1), agent: "Claude Code",
                                  sessionID: "s", processes: [ProcessIdentity(pid: 5, startTime: 9)]))
        try inbox.post(InboxEvent(kind: .activity, date: Date(timeIntervalSince1970: 2)))
        #expect(inbox.hasPending)
        let events = inbox.drain()
        #expect(events.map(\.kind) == [.sessionEnded, .activity])
        #expect(events.first?.processes == [ProcessIdentity(pid: 5, startTime: 9)])
        #expect(!inbox.hasPending)
        #expect(inbox.drain().isEmpty)
    }
}

@Suite struct HookInstallerTests {
    private func temporaryFile(_ contents: String?) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hooks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("settings.json")
        if let contents { try Data(contents.utf8).write(to: file) }
        return file
    }

    private func json(_ url: URL) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
    }

    @Test func installIsIdempotentAndKeepsOtherSettings() throws {
        let file = try temporaryFile(#"{"model":"opus","hooks":{"SessionEnd":[{"hooks":[{"type":"command","command":"node other.mjs"}]}],"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let installer = HookInstaller(agent: .claude, executable: "/Applications/MemSlop.app/Contents/Helpers/memslop", file: file)
        #expect(installer.status() == .notInstalled)
        #expect(try installer.install())
        #expect(try installer.install() == false)
        #expect(installer.status() == .installed)

        let root = try json(file)
        #expect(root["model"] as? String == "opus")
        let hooks = root["hooks"] as? [String: Any]
        #expect((hooks?["Stop"] as? [Any])?.count == 1)
        let commands = HookInstaller.entries(in: root).compactMap { $0["command"] as? String }
        #expect(commands.count == 2)
        #expect(commands.contains("node other.mjs"))
        #expect(commands.filter { $0.contains("hook session-end --agent claude") }.count == 1)
        #expect(FileManager.default.fileExists(atPath: file.path + ".memslop-backup"))

        #expect(try installer.uninstall())
        #expect(try installer.uninstall() == false)
        let after = try json(file)
        #expect(HookInstaller.entries(in: after).compactMap { $0["command"] as? String } == ["node other.mjs"])
        #expect(after["model"] as? String == "opus")
    }

    @Test func createsTheFileWhenMissingAndReplacesAnOldPath() throws {
        let file = try temporaryFile(nil)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try HookInstaller(agent: .codex, executable: "/old/MemSlop.app/Contents/Helpers/memslop", file: file).install()
        let current = HookInstaller(agent: .codex, executable: "/Applications/MemSlop.app/Contents/Helpers/memslop", file: file)
        #expect(try current.install())
        let commands = HookInstaller.entries(in: try json(file)).compactMap { $0["command"] as? String }
        #expect(commands == [current.command])
        try current.uninstall()
        #expect(try json(file).isEmpty)
    }

    @Test func refusesToTouchBrokenJSON() throws {
        let file = try temporaryFile("{ not json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        #expect(throws: HookInstaller.Failure.self) {
            try HookInstaller(agent: .claude, executable: "/x/memslop", file: file).install()
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == "{ not json")
    }

    @Test func quotesPathsWithSpaces() {
        let installer = HookInstaller(agent: .claude, executable: "/Users/me/My Apps/MemSlop.app/Contents/Helpers/memslop", file: URL(fileURLWithPath: "/tmp/x.json"))
        #expect(installer.command == "'/Users/me/My Apps/MemSlop.app/Contents/Helpers/memslop' hook session-end --agent claude")
    }
}

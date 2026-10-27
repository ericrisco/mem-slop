import Foundation
import Testing
@testable import MemSlopCore

/// A small world: a process tree, a tracker fed over time, and the policy.
private struct World {
    var processes: [ProcessSample] = []
    var nodes: [Int32: ProcessNode] = [
        1: ProcessNode(pid: 1, ppid: 0, name: "launchd", executablePath: "/sbin/launchd"),
    ]
    var tracker = IdleTracker()
    var configuration = ReaperConfiguration()
    let start = Date(timeIntervalSince1970: 1_000_000)

    @discardableResult
    mutating func add(_ process: ProcessSample) -> ProcessSample {
        processes.append(process)
        nodes[process.pid] = ProcessNode(pid: process.pid, ppid: process.ppid, name: process.name, executablePath: process.executablePath)
        return process
    }

    mutating func host(pid: Int32, ppid: Int32 = 1, name: String, path: String) {
        nodes[pid] = ProcessNode(pid: pid, ppid: ppid, name: name, executablePath: path)
    }

    /// Feeds the tracker every 30 s for `minutes`, burning `cpuPerTick` ns of CPU per tick in the given PIDs.
    mutating func advance(minutes: Int, busy: Set<Int32> = [], cpuPerTick: UInt64 = 3_000_000_000) -> Date {
        var now = start
        for tick in 0...(minutes * 2) {
            now = start.addingTimeInterval(TimeInterval(tick * 30))
            processes = processes.map { process in
                guard busy.contains(process.pid) else { return process }
                return Fixture.process(pid: process.pid, ppid: process.ppid, name: process.name, path: process.executablePath,
                                       arguments: process.arguments, memoryMB: process.memoryBytes / 1_048_576,
                                       cpuTimeNanos: process.cpuTimeNanos + cpuPerTick, startTime: process.id.startTime)
            }
            tracker.record(processes, at: now)
        }
        return now
    }

    func candidates(at now: Date, apps: Set<Int32> = [], kept: Set<ProcessIdentity> = []) -> [ReapCandidate] {
        let snapshot = MonitorSnapshot(timestamp: now, system: SystemSnapshot(), processes: processes, tree: nodes)
        return ReaperPolicy(configuration: configuration)
            .candidates(in: snapshot, tracker: tracker, regularAppPIDs: apps, kept: kept, now: now)
    }
}

@Suite struct ReaperPolicyTests {
    @Test func orphanedIdleServerIsCandidate() {
        var world = World()
        world.add(Fixture.process(pid: 500, ppid: 1, name: "python3", arguments: ["python3", "-m", "http.server", "8000"]))
        let now = world.advance(minutes: 11)
        let candidates = world.candidates(at: now)
        #expect(candidates.map(\.process.pid) == [500])
        #expect(candidates.first?.ancestry == .orphaned)
        #expect(candidates.first?.rule == "Python http.server")
    }

    @Test func serverAttachedToTerminalIsNeverCandidate() {
        var world = World()
        world.host(pid: 100, name: "Terminal", path: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal")
        world.host(pid: 101, ppid: 100, name: "login", path: "/usr/bin/login")
        world.host(pid: 102, ppid: 101, name: "zsh", path: "/bin/zsh")
        world.add(Fixture.process(pid: 500, ppid: 102, name: "python3", arguments: ["python3", "-m", "http.server"]))
        let now = world.advance(minutes: 30)
        #expect(world.candidates(at: now).isEmpty)
    }

    @Test func serverStartedByClaudeCodeIsCandidate() {
        var world = World()
        world.host(pid: 100, name: "iTerm2", path: "/Applications/iTerm.app/Contents/MacOS/iTerm2")
        world.host(pid: 101, ppid: 100, name: "zsh", path: "/bin/zsh")
        world.add(Fixture.process(pid: 200, ppid: 101, name: "claude", path: "/Users/me/.local/bin/claude", memoryMB: 300))
        world.host(pid: 201, ppid: 200, name: "zsh", path: "/bin/zsh")
        world.add(Fixture.process(pid: 300, ppid: 201, name: "node", path: "/opt/homebrew/bin/node",
                                  arguments: ["node", "/app/node_modules/.bin/next", "next dev"]))
        let now = world.advance(minutes: 11, busy: [200])
        let candidates = world.candidates(at: now)
        #expect(candidates.map(\.process.pid) == [300])
        #expect(candidates.first?.ancestry == .agentSpawned(agent: "Claude Code"))
    }

    @Test func agentInsideNodeIsRecognised() {
        var world = World()
        world.add(Fixture.process(pid: 200, ppid: 1, name: "node",
                                  arguments: ["node", "/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js"]))
        world.add(Fixture.process(pid: 300, ppid: 200, name: "uvicorn", arguments: ["uvicorn", "main:app"]))
        let now = world.advance(minutes: 11, busy: [200])
        #expect(world.candidates(at: now).first?.ancestry == .agentSpawned(agent: "Claude Code"))
    }

    @Test func busyServerIsNotCandidate() {
        var world = World()
        world.add(Fixture.process(pid: 500, ppid: 1, name: "uvicorn", arguments: ["uvicorn", "main:app"]))
        let now = world.advance(minutes: 11, busy: [500])
        #expect(world.candidates(at: now).isEmpty)
    }

    @Test func youngerThanWindowIsNotCandidate() {
        var world = World()
        world.add(Fixture.process(pid: 500, ppid: 1, name: "uvicorn", arguments: ["uvicorn", "main:app"]))
        let now = world.advance(minutes: 9)
        #expect(world.candidates(at: now).isEmpty)
    }

    @Test func regularAppsAreNeverCandidatesUnlessRuleAllows() {
        var world = World()
        world.add(Fixture.process(pid: 600, ppid: 1, name: "Discord", path: "/Applications/Discord.app/Contents/MacOS/Discord",
                                  arguments: ["Discord", "--remote-debugging-port=9222"]))
        world.add(Fixture.process(pid: 700, ppid: 1, name: "Electron", path: "/Applications/Obsidian.app/Contents/MacOS/Obsidian",
                                  arguments: ["Obsidian", "--headless"]))
        world.add(Fixture.process(pid: 800, ppid: 1, name: "Google Chrome for Testing",
                                  path: "/Users/me/Library/Caches/ms-playwright/chromium-1/chrome-mac/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"))
        let now = world.advance(minutes: 11)
        let pids = world.candidates(at: now, apps: [600, 700, 800]).map(\.process.pid)
        #expect(pids == [800])
    }

    @Test func protectedListWins() {
        var world = World()
        world.add(Fixture.process(pid: 500, ppid: 1, name: "uvicorn", arguments: ["uvicorn", "main:app"]))
        world.configuration.protected.append(ProcessRule(name: "My API", field: .command, pattern: "main:app"))
        let now = world.advance(minutes: 11)
        #expect(world.candidates(at: now).isEmpty)
    }

    @Test func keptProcessesAreSkipped() {
        var world = World()
        let server = world.add(Fixture.process(pid: 500, ppid: 1, name: "uvicorn", arguments: ["uvicorn", "main:app"]))
        let now = world.advance(minutes: 11)
        #expect(world.candidates(at: now, kept: [server.id]).isEmpty)
    }

    @Test func idleParentWithBusyChildIsSpared() {
        var world = World()
        world.add(Fixture.process(pid: 400, ppid: 1, name: "npm", arguments: ["npm", "run", "dev"]))
        world.add(Fixture.process(pid: 401, ppid: 400, name: "node", arguments: ["node", "next dev"]))
        let now = world.advance(minutes: 11, busy: [401])
        #expect(world.candidates(at: now).isEmpty)
    }

    @Test func disabledRuleDoesNotMatch() {
        var world = World()
        world.add(Fixture.process(pid: 500, ppid: 1, name: "uvicorn", arguments: ["uvicorn", "main:app"]))
        world.configuration.rules = world.configuration.rules.map { rule in
            var rule = rule
            if rule.name == "Uvicorn" { rule.isEnabled = false }
            return rule
        }
        let now = world.advance(minutes: 11)
        #expect(world.candidates(at: now).isEmpty)
    }

    @Test func intervalDefinesTheWindow() {
        var world = World()
        world.configuration.intervalMinutes = 30
        world.add(Fixture.process(pid: 500, ppid: 1, name: "uvicorn", arguments: ["uvicorn", "main:app"]))
        let early = world.advance(minutes: 20)
        #expect(world.candidates(at: early).isEmpty)
        var later = World()
        later.configuration.intervalMinutes = 30
        later.add(Fixture.process(pid: 500, ppid: 1, name: "uvicorn", arguments: ["uvicorn", "main:app"]))
        let late = later.advance(minutes: 31)
        #expect(later.candidates(at: late).count == 1)
    }

    @Test func memoryGrowthMeansNotIdle() {
        var tracker = IdleTracker()
        let start = Date(timeIntervalSince1970: 0)
        for tick in 0...22 {
            let process = Fixture.process(pid: 9, name: "uvicorn", memoryMB: 100 + UInt64(tick) * 5)
            tracker.record([process], at: start.addingTimeInterval(TimeInterval(tick * 30)))
        }
        let last = Fixture.process(pid: 9, name: "uvicorn", memoryMB: 210)
        let activity = tracker.activity(of: last, over: 600, now: start.addingTimeInterval(660))
        #expect((activity?.memoryChange ?? 0) > 20 * 1_048_576)
    }
}

@Suite struct IdleTrackerTests {
    @Test func sleepGapResetsHistory() {
        var tracker = IdleTracker()
        let process = Fixture.process(pid: 9, name: "uvicorn")
        let start = Date(timeIntervalSince1970: 0)
        for tick in 0...20 { tracker.record([process], at: start.addingTimeInterval(TimeInterval(tick * 30))) }
        let afterSleep = start.addingTimeInterval(4 * 3600)
        tracker.record([process], at: afterSleep)
        #expect(tracker.activity(of: process, over: 600, now: afterSleep) == nil)
    }

    @Test func pidReuseDoesNotInheritHistory() {
        var tracker = IdleTracker()
        let old = Fixture.process(pid: 9, name: "uvicorn", startTime: 1)
        let start = Date(timeIntervalSince1970: 0)
        for tick in 0...22 { tracker.record([old], at: start.addingTimeInterval(TimeInterval(tick * 30))) }
        let reused = Fixture.process(pid: 9, name: "uvicorn", startTime: 2)
        let now = start.addingTimeInterval(23 * 30)
        tracker.record([reused], at: now)
        #expect(tracker.activity(of: reused, over: 600, now: now) == nil)
    }
}

@Suite struct RuleTests {
    @Test func matchesByField() {
        let process = Fixture.process(name: "Discord", path: "/Applications/Discord.app/Contents/MacOS/Discord",
                                      arguments: ["Discord", "--type=renderer"])
        #expect(ProcessRule(name: "a", field: .executable, pattern: "discord").matches(process))
        #expect(ProcessRule(name: "a", field: .command, pattern: "TYPE=RENDERER").matches(process))
        #expect(ProcessRule(name: "a", field: .path, pattern: "Discord.app").matches(process))
        #expect(ProcessRule(name: "a", field: .app, pattern: "Discord").matches(process))
        #expect(!ProcessRule(name: "a", field: .app, pattern: "Disc").matches(process))
    }

    @Test func byteTextSearchIsCaseInsensitive() {
        let text = ByteText("node /Users/Me/app/node_modules/.bin/NEXT dev --port 3000")
        #expect(text.contains("next dev"))
        #expect(text.contains("NODE_MODULES"))
        #expect(!text.contains("vite"))
        #expect(text.contains(""))
        #expect(!ByteText("ab").contains("abc"))
    }

    @Test func emptyPatternIsInvalidAndNeverMatches() {
        let rule = ProcessRule(name: "Bad", field: .command, pattern: "  ")
        #expect(!rule.isValid)
        #expect(!rule.matches(Fixture.process(name: "anything")))
    }

    @Test func configurationRoundTripsThroughJSON() throws {
        var configuration = ReaperConfiguration()
        configuration.intervalMinutes = 20
        configuration.rules.append(ProcessRule(name: "Custom", field: .executable, pattern: "my-server"))
        let data = try JSONEncoder().encode(configuration)
        #expect(try JSONDecoder().decode(ReaperConfiguration.self, from: data) == configuration)
    }
}

@Suite struct ActivityLogTests {
    @Test func persistsAndPrunes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("memslop-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let now = Date()
        var log = ActivityLog(fileURL: url)
        log.append([
            entry(date: now.addingTimeInterval(-25 * 3600), outcome: .quit),
            entry(date: now.addingTimeInterval(-60), outcome: .quit),
            entry(date: now.addingTimeInterval(-30), outcome: .wouldQuit),
        ], now: now)
        #expect(log.entries.count == 2)
        let reloaded = ActivityLog(fileURL: url)
        #expect(reloaded.entries.count == 2)
        #expect(reloaded.freedMemory(since: now.addingTimeInterval(-3600)) == 50 * 1_048_576)
    }

    private func entry(date: Date, outcome: ActivityEntry.Outcome) -> ActivityEntry {
        ActivityEntry(date: date, name: "uvicorn", pid: 1, group: "Python", rule: "Uvicorn", reason: "orphaned",
                      memoryBytes: 50 * 1_048_576, commandLine: "uvicorn main:app", outcome: outcome)
    }
}

@Suite struct GraceTests {
    @Test func requestDuringGraceSparesProcess() {
        let before = Fixture.process(pid: 9, name: "uvicorn", cpuTimeNanos: 1_000_000_000)
        let quiet = Fixture.process(pid: 9, name: "uvicorn", cpuTimeNanos: 1_002_000_000)
        let served = Fixture.process(pid: 9, name: "uvicorn", cpuTimeNanos: 1_300_000_000)
        #expect(!ReaperPolicy.wasActive(before: before, after: quiet, memoryFloor: 10 * 1_048_576))
        #expect(ReaperPolicy.wasActive(before: before, after: served, memoryFloor: 10 * 1_048_576))
    }
}

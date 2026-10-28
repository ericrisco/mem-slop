import Darwin
import Foundation
import Testing
@testable import MemSlopCore

@Suite struct ProjectResolverTests {
    private func resolver(_ existing: Set<String>) -> ProjectResolver {
        ProjectResolver(home: "/Users/dev", exists: { existing.contains($0) })
    }

    @Test func nearestAncestorWithMarkerWins() {
        let resolver = resolver(["/Users/dev/code/shop/.git", "/Users/dev/code/shop/web/package.json"])
        #expect(resolver.project(for: "/Users/dev/code/shop/web/src")?.path == "/Users/dev/code/shop/web")
        #expect(resolver.project(for: "/Users/dev/code/shop/api")?.path == "/Users/dev/code/shop")
    }

    @Test func noMarkerFallsBackToTheDirectory() {
        let project = resolver([]).project(for: "/Users/dev/scratch/demo")
        #expect(project?.path == "/Users/dev/scratch/demo")
        #expect(project?.name == "demo")
    }

    @Test func rootAndHomeAreNotProjects() {
        let resolver = resolver(["/Users/dev/package.json"])
        #expect(resolver.project(for: "/") == nil)
        #expect(resolver.project(for: "/Users/dev") == nil)
        #expect(resolver.project(for: nil) == nil)
        #expect(resolver.project(for: "/Users/dev/Library/Containers/com.example/Data") == nil)
        #expect(resolver.project(for: "/Users/dev/.codex/plugins/cache/thing") == nil)
        #expect(resolver.project(for: "/System/Library/Frameworks/WebKit.framework") == nil)
        #expect(resolver.project(for: "/private/var/folders/xy/T/thing") == nil)
        // A manifest in the home folder does not swallow every subfolder.
        #expect(resolver.project(for: "/Users/dev/notes")?.path == "/Users/dev/notes")
    }
}

@Suite struct ProcessInspectorTests {
    @Test func seesOwnListeningPortAndWorkingDirectory() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        try #require(fd >= 0)
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        try #require(bound == 0)
        try #require(listen(fd, 1) == 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        let port = UInt16(bigEndian: address.sin_port)

        #expect(ProcessInspector.listeningPorts(getpid()).contains(port))
        let cwd = FileManager.default.currentDirectoryPath
        #expect(ProcessInspector.workingDirectory(getpid()).map { ($0 as NSString).resolvingSymlinksInPath } == (cwd as NSString).resolvingSymlinksInPath)
    }

    @Test func samplerFillsContextOnlyWhenAsked() {
        let sampler = ProcessSampler()
        let plain = sampler.sample(includeContext: false).processes.first { $0.pid == getpid() }
        #expect(plain?.context.workingDirectory == nil)
        let rich = sampler.sample(includeContext: true).processes.first { $0.pid == getpid() }
        #expect(rich?.context.workingDirectory != nil)
    }
}

@Suite struct ProjectGroupingTests {
    @Test func groupsServersOfOneRepositoryTogether() {
        let shop = Project(path: "/Users/dev/shop")
        var next = Fixture.process(name: "node", arguments: ["node", "next", "dev"], memoryMB: 400)
        next.context = ProcessContext(ports: [3000], project: shop)
        var api = Fixture.process(name: "python3", arguments: ["python3", "-m", "uvicorn", "main:app"], memoryMB: 200)
        api.context = ProcessContext(ports: [8000], project: shop)
        let loose = Fixture.process(name: "python3", arguments: ["python3", "script.py"])
        var chrome = Fixture.process(name: "Google Chrome", path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
        chrome.context = ProcessContext(project: shop)

        let groups = ProcessGrouper().group([next, api, loose, chrome], sortedBy: .memory, mode: .project)
        let project = groups.first { $0.id == "project:/Users/dev/shop" }
        #expect(project?.name == "shop")
        #expect(project?.processes.count == 2)
        #expect(project?.ports == [3000, 8000])
        #expect(groups.contains { $0.id == "family:python" })
        #expect(groups.contains { $0.id.hasPrefix("app:") })

        let byKind = ProcessGrouper().group([next, api, loose], sortedBy: .memory)
        #expect(!byKind.contains { $0.id.hasPrefix("project:") })
    }
}

@Suite struct PressureTriggerTests {
    @Test func firesAfterSustainedCriticalPressureWithCooldown() {
        var trigger = PressureTrigger(delay: 30, cooldown: 300)
        let start = Date(timeIntervalSince1970: 1_000)
        do { let fired = trigger.observe(.critical, at: start); #expect(!fired) }
        do { let fired = trigger.observe(.critical, at: start + 20); #expect(!fired) }
        do { let fired = trigger.observe(.critical, at: start + 31); #expect(fired) }
        do { let fired = trigger.observe(.critical, at: start + 120); #expect(!fired) }
        do { let fired = trigger.observe(.critical, at: start + 332); #expect(fired) }
    }

    @Test func calmPressureResetsTheClock() {
        var trigger = PressureTrigger(delay: 30, cooldown: 300)
        let start = Date(timeIntervalSince1970: 1_000)
        _ = trigger.observe(.critical, at: start)
        _ = trigger.observe(.warning, at: start + 20)
        do { let fired = trigger.observe(.critical, at: start + 35); #expect(!fired) }
        do { let fired = trigger.observe(.critical, at: start + 66); #expect(fired) }
    }
}

@Suite struct ConfigurationCompatibilityTests {
    @Test func olderSettingsKeepTheirRulesAndGainNewDefaults() throws {
        let legacy = #"{"isEnabled":false,"intervalMinutes":30,"rules":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Mine","field":"command","pattern":"my-server","isEnabled":true,"matchesApps":false}]}"#
        let configuration = try JSONDecoder().decode(ReaperConfiguration.self, from: Data(legacy.utf8))
        #expect(configuration.isEnabled == false)
        #expect(configuration.intervalMinutes == 30)
        #expect(configuration.rules.map(\.name) == ["Mine"])
        #expect(configuration.cleanOnPressure)
        #expect(configuration.protected == ProcessRule.defaultProtected)
        #expect(configuration.pressureWindow == 300)
    }

    @Test func roundTrips() throws {
        var configuration = ReaperConfiguration()
        configuration.cleanOnPressure = false
        configuration.intervalMinutes = 15
        let decoded = try JSONDecoder().decode(ReaperConfiguration.self, from: JSONEncoder().encode(configuration))
        #expect(decoded == configuration)
    }
}

@Suite struct SavingsCounterTests {
    @Test func countsOnlyFreedMemoryAndPersists() throws {
        func entry(_ outcome: ActivityEntry.Outcome, _ mb: UInt64) -> ActivityEntry {
            ActivityEntry(date: Date(), name: "node", pid: 1, group: "Node.js", rule: "Manual", reason: "", memoryBytes: mb * 1_048_576, commandLine: "", outcome: outcome)
        }
        var counter = SavingsCounter()
        counter.add([entry(.quit, 300), entry(.forced, 100), entry(.kept, 900), entry(.wouldQuit, 900), entry(.failed, 50)])
        #expect(counter.totalBytes == 400 * 1_048_576)
        #expect(counter.processCount == 2)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("savings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        counter.save(to: url)
        let loaded = SavingsCounter.load(from: url)
        #expect(loaded.totalBytes == counter.totalBytes)
        #expect(loaded.processCount == 2)
        #expect(loaded.since != nil)
    }
}

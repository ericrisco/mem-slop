import Foundation
import Testing
@testable import MemSlopCore

@Suite(.serialized) struct TerminatorTests {
    private func spawn(_ script: String) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try process.run()
        return process
    }

    @Test func terminatesGracefully() async throws {
        let process = try spawn("exec sleep 60")
        try await Task.sleep(for: .milliseconds(100))
        let identity = try #require(ProcessTerminator.identity(of: process.processIdentifier))
        let result = await ProcessTerminator(gracePeriod: .seconds(2)).terminate(identity)
        #expect(result == .terminated)
        #expect(!ProcessTerminator.isAlive(identity))
    }

    @Test func forcesProcessThatIgnoresTerm() async throws {
        let process = try spawn("trap '' TERM; while true; do sleep 0.1; done")
        try await Task.sleep(for: .milliseconds(200))
        let identity = try #require(ProcessTerminator.identity(of: process.processIdentifier))
        let result = await ProcessTerminator(gracePeriod: .milliseconds(500)).terminate(identity)
        #expect(result == .killed)
    }

    @Test func reportsNotRunningForStaleIdentity() async {
        let stale = ProcessIdentity(pid: getpid(), startTime: 42)
        #expect(await ProcessTerminator().terminate(stale) == .notRunning)
    }

    @Test func refusesRootProcess() async throws {
        let launchd = try #require(ProcessTerminator.identity(of: 1))
        #expect(await ProcessTerminator().terminate(launchd) == .permissionDenied)
    }
}

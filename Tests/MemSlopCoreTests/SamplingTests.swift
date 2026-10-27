import Foundation
import Testing
@testable import MemSlopCore

@Suite struct SamplingTests {
    @Test func parsesProcArgs() {
        var buffer: [UInt8] = []
        withUnsafeBytes(of: Int32(3)) { buffer.append(contentsOf: $0) }
        let parts: [String] = ["/usr/bin/python3", "", "", "python3", "-m", "http.server", "PATH=/usr/bin"]
        for part in parts {
            buffer.append(contentsOf: Array(part.utf8))
            buffer.append(0)
        }
        #expect(ProcessSampler.parseProcArgs(buffer) == ["python3", "-m", "http.server"])
    }

    @Test func parsesEmptyBuffer() {
        #expect(ProcessSampler.parseProcArgs([]) == [])
    }

    @Test func liveSampleFindsCurrentProcess() async throws {
        let sampler = Sampler()
        _ = await sampler.sample()
        try await Task.sleep(for: .milliseconds(200))
        let snapshot = await sampler.sample()
        let me = try #require(snapshot.processes.first { $0.pid == getpid() })
        #expect(me.memoryBytes > 0)
        #expect(!me.executablePath.isEmpty)
        #expect(snapshot.system.memoryTotal > 0)
        #expect(snapshot.system.memoryUsed > 0)
        #expect((0...1).contains(snapshot.system.cpuUsage))
        #expect(snapshot.tree[1] != nil, "launchd is visible in the tree")
    }
}

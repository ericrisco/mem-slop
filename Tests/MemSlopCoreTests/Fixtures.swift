import Foundation
@testable import MemSlopCore

enum Fixture {
    private static let counter = Counter()

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Int32 = 1000
        func next() -> Int32 { lock.lock(); defer { lock.unlock() }; value += 1; return value }
    }

    static func process(
        pid: Int32? = nil, ppid: Int32 = 1, name: String, path: String? = nil, arguments: [String] = [],
        cpu: Double = 0, memoryMB: UInt64 = 10, cpuTimeNanos: UInt64 = 0, startTime: UInt64 = 1
    ) -> ProcessSample {
        let pid = pid ?? counter.next()
        return ProcessSample(
            id: ProcessIdentity(pid: pid, startTime: startTime), ppid: ppid, uid: 501, name: name,
            executablePath: path ?? "/usr/bin/\(name)", arguments: arguments.isEmpty ? [name] : arguments,
            cpuPercent: cpu, memoryBytes: memoryMB * 1_048_576, cpuTimeNanos: cpuTimeNanos,
            startDate: Date(timeIntervalSince1970: 0)
        )
    }
}

import Darwin
import Foundation

/// Reads host-wide CPU and memory statistics from Mach.
public final class SystemSampler {
    private let host = mach_host_self()
    private var previousTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private let pageSize = UInt64(getpagesize())

    public init() {}

    public func sample() -> SystemSnapshot {
        var snapshot = SystemSnapshot()
        snapshot.coreCount = ProcessInfo.processInfo.activeProcessorCount
        sampleCPU(into: &snapshot)
        sampleMemory(into: &snapshot)
        snapshot.pressure = Self.memoryPressure()
        snapshot.swapUsed = Self.swapUsed()
        var load = [Double](repeating: 0, count: 3)
        if getloadavg(&load, 3) == 3 { snapshot.loadAverage = load }
        return snapshot
    }

    private func sampleCPU(into snapshot: inout SystemSnapshot) {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let ticks = (
            user: UInt64(info.cpu_ticks.0), system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2), nice: UInt64(info.cpu_ticks.3)
        )
        defer { previousTicks = ticks }
        guard let previous = previousTicks else { return }
        let user = Double(ticks.user &- previous.user) + Double(ticks.nice &- previous.nice)
        let system = Double(ticks.system &- previous.system)
        let idle = Double(ticks.idle &- previous.idle)
        let total = user + system + idle
        guard total > 0 else { return }
        snapshot.cpuUser = user / total
        snapshot.cpuSystem = system / total
        snapshot.cpuUsage = (user + system) / total
    }

    private func sampleMemory(into snapshot: inout SystemSnapshot) {
        snapshot.memoryTotal = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let app = (internalPages > purgeable ? internalPages - purgeable : 0) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        snapshot.memoryApp = app
        snapshot.memoryWired = wired
        snapshot.memoryCompressed = compressed
        snapshot.memoryCached = (UInt64(stats.external_page_count) + purgeable) * pageSize
        snapshot.memoryUsed = min(snapshot.memoryTotal, app + wired + compressed)
    }

    static func memoryPressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        return MemoryPressure(rawValue: Int(level)) ?? .normal
    }

    static func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }
}

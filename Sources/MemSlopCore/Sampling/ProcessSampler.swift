import Darwin
import Foundation

/// Enumerates processes with libproc and computes per-process CPU % between calls.
public final class ProcessSampler {
    private struct Previous {
        var cpuTimeNanos: UInt64
        var wallNanos: UInt64
    }

    private var previous: [ProcessIdentity: Previous] = [:]
    private var argumentsCache: [ProcessIdentity: [String]] = [:]
    private var pathCache: [ProcessIdentity: String] = [:]
    private var contextCache: [ProcessIdentity: (context: ProcessContext, refreshed: UInt64)] = [:]
    private let projects = ProjectResolver()
    /// Ports and working directory change rarely; re-read them at most this often per process.
    public var contextRefreshNanos: UInt64 = 15_000_000_000
    private let timebase: (numer: UInt64, denom: UInt64)
    private let currentUID = getuid()

    public init() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        timebase = (UInt64(info.numer), UInt64(max(info.denom, 1)))
    }

    /// Returns the inspectable processes of the current user plus the full process tree.
    /// - Parameter includeContext: also read listening ports and project folders (cached).
    public func sample(includeContext: Bool = false) -> (processes: [ProcessSample], tree: [Int32: ProcessNode]) {
        let now = UInt64(DispatchTime.now().uptimeNanoseconds)
        var processes: [ProcessSample] = []
        var tree: [Int32: ProcessNode] = [:]
        var seen = Set<ProcessIdentity>()

        for entry in Self.kernelProcesses() where entry.pid > 0 {
            let pid = entry.pid
            let identity = entry.identity
            let path = cachedPath(identity)
            let name = path.isEmpty ? entry.command : (path as NSString).lastPathComponent
            tree[pid] = ProcessNode(pid: pid, ppid: entry.ppid, name: name, executablePath: path)

            guard entry.uid == currentUID, !entry.isZombie, let usage = Self.resourceUsage(pid) else { continue }
            seen.insert(identity)
            let cpuTime = (usage.ri_user_time + usage.ri_system_time) * timebase.numer / timebase.denom
            var cpuPercent = 0.0
            if let last = previous[identity], now > last.wallNanos, cpuTime >= last.cpuTimeNanos {
                cpuPercent = Double(cpuTime - last.cpuTimeNanos) / Double(now - last.wallNanos) * 100
            }
            previous[identity] = Previous(cpuTimeNanos: cpuTime, wallNanos: now)

            var sample = ProcessSample(
                id: identity,
                ppid: entry.ppid,
                uid: entry.uid,
                name: name,
                executablePath: path,
                arguments: cachedArguments(identity),
                cpuPercent: cpuPercent,
                memoryBytes: usage.ri_phys_footprint,
                cpuTimeNanos: cpuTime,
                startDate: Date(timeIntervalSince1970: TimeInterval(identity.startTime) / 1_000_000)
            )
            if includeContext {
                sample.context = context(identity, now: now)
            } else if let cached = contextCache[identity] {
                sample.context = cached.context
            }
            processes.append(sample)
        }

        previous = previous.filter { seen.contains($0.key) }
        contextCache = contextCache.filter { seen.contains($0.key) }
        argumentsCache = argumentsCache.filter { seen.contains($0.key) }
        pathCache = pathCache.filter { tree[$0.key.pid] != nil }
        return (processes, tree)
    }

    private func context(_ identity: ProcessIdentity, now: UInt64) -> ProcessContext {
        if let cached = contextCache[identity], now - cached.refreshed < contextRefreshNanos { return cached.context }
        let directory = ProcessInspector.workingDirectory(identity.pid)
        let context = ProcessContext(
            ports: ProcessInspector.listeningPorts(identity.pid),
            workingDirectory: directory,
            project: projects.project(for: directory)
        )
        contextCache[identity] = (context, now)
        return context
    }

    private func cachedPath(_ identity: ProcessIdentity) -> String {
        if let path = pathCache[identity] { return path }
        let path = Self.executablePath(identity.pid)
        pathCache[identity] = path
        return path
    }

    private func cachedArguments(_ identity: ProcessIdentity) -> [String] {
        if let arguments = argumentsCache[identity] { return arguments }
        let arguments = Self.arguments(identity.pid)
        argumentsCache[identity] = arguments
        return arguments
    }

    // MARK: - libproc wrappers

    /// A row of the kernel process table (visible for every user, unlike libproc's BSD info).
    public struct KernelProcess: Sendable {
        public let pid: Int32
        public let ppid: Int32
        public let uid: UInt32
        public let command: String
        public let startTime: UInt64
        public let isZombie: Bool

        public var identity: ProcessIdentity { ProcessIdentity(pid: pid, startTime: startTime) }

        init(_ info: kinfo_proc) {
            var info = info
            pid = info.kp_proc.p_pid
            ppid = info.kp_eproc.e_ppid
            uid = info.kp_eproc.e_ucred.cr_uid
            command = withUnsafeBytes(of: &info.kp_proc.p_comm) { ProcessSampler.cString(from: $0) }
            startTime = UInt64(info.kp_proc.p_starttime.tv_sec) * 1_000_000 + UInt64(info.kp_proc.p_starttime.tv_usec)
            isZombie = info.kp_proc.p_stat == CChar(SZOMB)
        }
    }

    public static func kernelProcesses() -> [KernelProcess] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        size += size / 8
        var buffer = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
        guard sysctl(&mib, 4, &buffer, &size, nil, 0) == 0 else { return [] }
        return buffer.prefix(size / MemoryLayout<kinfo_proc>.stride).map(KernelProcess.init)
    }

    public static func kernelProcess(_ pid: pid_t) -> KernelProcess? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return KernelProcess(info)
    }

    static func resourceUsage(_ pid: pid_t) -> rusage_info_v4? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? usage : nil
    }

    static func executablePath(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static let argumentsMax: Int = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("kern.argmax", &value, &size, nil, 0) == 0 ? Int(value) : 256 * 1024
    }()

    static func arguments(_ pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = argumentsMax
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }
        return parseProcArgs(Array(buffer.prefix(size)))
    }

    /// Parses a `KERN_PROCARGS2` buffer: argc, exec path, padding, then argc NUL-terminated args.
    public static func parseProcArgs(_ buffer: [UInt8]) -> [String] {
        guard buffer.count > MemoryLayout<Int32>.size else { return [] }
        let argc = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc > 0 else { return [] }
        var index = MemoryLayout<Int32>.size
        while index < buffer.count, buffer[index] != 0 { index += 1 }   // exec path
        while index < buffer.count, buffer[index] == 0 { index += 1 }   // padding
        var arguments: [String] = []
        while arguments.count < Int(argc), index < buffer.count {
            let start = index
            while index < buffer.count, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }

    static func cString(from bytes: UnsafeRawBufferPointer) -> String {
        let end = bytes.firstIndex(of: 0) ?? bytes.count
        return String(decoding: bytes[..<end], as: UTF8.self)
    }
}

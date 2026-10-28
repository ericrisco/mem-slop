import Darwin
import Foundation

/// Where a process runs and what it serves: listening TCP ports and its project folder.
public struct ProcessContext: Hashable, Sendable {
    /// Local TCP ports in LISTEN state, sorted.
    public var ports: [UInt16]
    public var workingDirectory: String?
    public var project: Project?

    public init(ports: [UInt16] = [], workingDirectory: String? = nil, project: Project? = nil) {
        self.ports = ports
        self.workingDirectory = workingDirectory
        self.project = project
    }

    public static let empty = ProcessContext()

    public var isEmpty: Bool { ports.isEmpty && project == nil }
}

/// A folder that looks like the root of a code project.
public struct Project: Hashable, Sendable, Codable {
    public let path: String
    public var name: String { (path as NSString).lastPathComponent }

    public init(path: String) {
        self.path = path
    }
}

/// Finds the project a working directory belongs to: the nearest ancestor with a VCS folder or a
/// package manifest. Results are cached per directory; folders rarely change shape.
public final class ProjectResolver: @unchecked Sendable {
    public static let markers = [".git", "package.json", "pyproject.toml", "Cargo.toml", "go.mod", "Gemfile", "composer.json", "Package.swift", "deno.json"]

    private let home: String
    private let exists: (String) -> Bool
    private var cache: [String: Project?] = [:]
    private let lock = NSLock()

    public init(home: String = NSHomeDirectory(), exists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.home = (home as NSString).standardizingPath
        self.exists = exists
    }

    /// System and app-data locations: a process running there is not working on a project.
    static let systemPrefixes = ["/System/", "/Library/", "/usr/", "/bin/", "/sbin/", "/private/var/", "/var/", "/Applications/", "/dev/"]

    public func project(for directory: String?) -> Project? {
        guard let directory, !directory.isEmpty else { return nil }
        let path = (directory as NSString).standardizingPath
        guard path != "/", path != home, !isSystemLocation(path) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[path] { return cached }
        let project = resolve(path)
        if cache.count > 2_000 { cache.removeAll() }
        cache[path] = project
        return project
    }

    private func isSystemLocation(_ path: String) -> Bool {
        if Self.systemPrefixes.contains(where: { path.hasPrefix($0) }) { return true }
        // ~/Library and dot-folders like ~/.codex or ~/.npm hold app data and caches.
        guard path.hasPrefix(home + "/") else { return false }
        let first = path.dropFirst(home.count + 1).split(separator: "/").first ?? ""
        return first == "Library" || first.hasPrefix(".")
    }

    private func resolve(_ path: String) -> Project? {
        var current = path
        // Stop at the home folder or the filesystem root: a manifest there is not a project.
        while current != "/", current != home, !current.isEmpty {
            if Self.markers.contains(where: { exists((current as NSString).appendingPathComponent($0)) }) {
                return Project(path: current)
            }
            current = (current as NSString).deletingLastPathComponent
        }
        return Project(path: path)
    }
}

/// libproc lookups for a single process. Only works for processes the current user owns.
public enum ProcessInspector {
    /// Local TCP ports the process listens on.
    public static func listeningPorts(_ pid: pid_t) -> [UInt16] {
        let stride = MemoryLayout<proc_fdinfo>.stride
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return [] }
        // Room for descriptors opened between the two calls.
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / stride + 16)
        let used = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &descriptors, Int32(descriptors.count * stride))
        guard used > 0 else { return [] }
        var ports = Set<UInt16>()
        for descriptor in descriptors.prefix(Int(used) / stride) where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var info = socket_fdinfo()
            let infoSize = Int32(MemoryLayout<socket_fdinfo>.stride)
            guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDSOCKETINFO, &info, infoSize) == infoSize,
                  info.psi.soi_kind == Int32(SOCKINFO_TCP) else { continue }
            let tcp = info.psi.soi_proto.pri_tcp
            guard tcp.tcpsi_state == Int32(TSI_S_LISTEN) else { continue }
            let port = UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport))
            if port != 0 { ports.insert(port) }
        }
        return ports.sorted()
    }

    /// Current working directory of the process.
    public static func workingDirectory(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { ProcessSampler.cString(from: $0) }
        return path.isEmpty ? nil : path
    }
}

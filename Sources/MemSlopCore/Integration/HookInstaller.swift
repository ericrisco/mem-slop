import Foundation

/// The agent CLIs MemSlop can hook into.
public enum AgentKind: String, CaseIterable, Sendable, Codable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    /// Where the agent reads user-level hooks. Both use the same `{"hooks": {"Event": [...]}}` shape.
    public func settingsFile(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        switch self {
        case .claude: home.appendingPathComponent(".claude/settings.json")
        case .codex: home.appendingPathComponent(".codex/hooks.json")
        }
    }
}

/// Adds and removes MemSlop's SessionEnd hook in an agent's settings file, leaving everything else as it was.
public struct HookInstaller: Sendable {
    public enum Status: Equatable, Sendable {
        case installed
        case notInstalled
        /// The agent is not set up on this Mac (no config folder).
        case agentMissing
    }

    public enum Failure: Error, CustomStringConvertible {
        case unreadable(URL)

        public var description: String {
            switch self {
            case let .unreadable(url): "\(url.path) is not valid JSON; fix or move it first."
            }
        }
    }

    public static let event = "SessionEnd"
    /// Every MemSlop hook command contains this, which is how we find our own entries.
    public static let marker = "hook session-end"

    public let agent: AgentKind
    public let file: URL
    /// Absolute path of the `memslop` executable the hook runs.
    public let executable: String

    public init(agent: AgentKind, executable: String, file: URL? = nil) {
        self.agent = agent
        self.executable = executable
        self.file = file ?? agent.settingsFile()
    }

    public var command: String {
        "'\(executable.replacingOccurrences(of: "'", with: "'\\''"))' \(Self.marker) --agent \(agent.rawValue)"
    }

    public func status() -> Status {
        guard FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path) else { return .agentMissing }
        guard let root = try? read() else { return .notInstalled }
        return Self.entries(in: root).contains(where: Self.isOurs) ? .installed : .notInstalled
    }

    /// Adds the hook (replacing an older MemSlop hook). Returns false if it was already exactly there.
    @discardableResult
    public func install() throws -> Bool {
        var root = try read() ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var groups = hooks[Self.event] as? [[String: Any]] ?? []
        let ours: [String: Any] = ["type": "command", "command": command, "timeout": 5]
        if groups.contains(where: { ($0["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String) == command } }) {
            return false
        }
        groups = Self.removingOurs(from: groups)
        groups.append(["hooks": [ours]])
        hooks[Self.event] = groups
        root["hooks"] = hooks
        try write(root)
        return true
    }

    /// Removes every MemSlop hook. Returns false if there was none.
    @discardableResult
    public func uninstall() throws -> Bool {
        guard var root = try read(), var hooks = root["hooks"] as? [String: Any],
              let groups = hooks[Self.event] as? [[String: Any]] else { return false }
        let cleaned = Self.removingOurs(from: groups)
        guard cleaned.count != groups.count || Self.entries(in: root).contains(where: Self.isOurs) else { return false }
        if cleaned.isEmpty { hooks[Self.event] = nil } else { hooks[Self.event] = cleaned }
        if hooks.isEmpty { root["hooks"] = nil } else { root["hooks"] = hooks }
        try write(root)
        return true
    }

    // MARK: - JSON

    static func isOurs(_ hook: [String: Any]) -> Bool {
        guard let command = hook["command"] as? String else { return false }
        return command.contains(marker) && command.lowercased().contains("memslop")
    }

    static func entries(in root: [String: Any]) -> [[String: Any]] {
        let groups = (root["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
        return groups.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
    }

    static func removingOurs(from groups: [[String: Any]]) -> [[String: Any]] {
        groups.compactMap { group in
            guard let hooks = group["hooks"] as? [[String: Any]] else { return group }
            let kept = hooks.filter { !isOurs($0) }
            if kept.isEmpty { return nil }
            var group = group
            group["hooks"] = kept
            return group
        }
    }

    private func read() throws -> [String: Any]? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.unreadable(file) }
        return root
    }

    private func write(_ root: [String: Any]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Keep the user's original once, the first time MemSlop touches the file.
        let backup = file.appendingPathExtension("memslop-backup")
        if FileManager.default.fileExists(atPath: file.path), !FileManager.default.fileExists(atPath: backup.path) {
            try? FileManager.default.copyItem(at: file, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try (data + Data("\n".utf8)).write(to: file, options: .atomic)
    }
}

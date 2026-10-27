import Foundation

/// Who started a process, judged by walking its parent chain.
public enum Ancestry: Hashable, Sendable {
    /// An AI agent CLI (Claude Code, Codex…) sits in the parent chain.
    case agentSpawned(agent: String)
    /// A live terminal, IDE or multiplexer owns it: the user is probably using it.
    case attached(host: String)
    /// Re-parented to launchd: whoever started it is gone.
    case orphaned

    public var isEligible: Bool {
        if case .attached = self { return false }
        return true
    }

    public var label: String {
        switch self {
        case let .agentSpawned(agent): "started by \(agent)"
        case let .attached(host): "attached to \(host)"
        case .orphaned: "orphaned"
        }
    }
}

public enum AncestryClassifier {
    static let hostApps: Set<String> = [
        "terminal", "iterm", "iterm2", "warp", "ghostty", "kitty", "alacritty", "wezterm", "hyper", "tabby", "rio",
        "visual studio code", "visual studio code - insiders", "code", "cursor", "windsurf", "zed", "xcode", "nova",
        "sublime text", "emacs", "macvim", "vimr", "intellij idea", "intellij idea ce", "pycharm", "pycharm ce",
        "webstorm", "goland", "rustrover", "clion", "phpstorm", "rider", "datagrip", "android studio", "fleet",
    ]
    static let hostExecutables: Set<String> = ["tmux", "screen", "zellij", "sshd", "mosh-server", "sshd-session"]
    static let agentExecutables: Set<String> = ["claude", "codex", "gemini", "aider", "opencode", "amp", "cursor-agent", "goose", "crush", "qwen"]

    /// - Parameters:
    ///   - process: the process to classify.
    ///   - tree: every visible process.
    ///   - arguments: command lines of the user's processes, to spot agents running inside `node`.
    public static func classify(_ process: ProcessSample, tree: [Int32: ProcessNode], arguments: [Int32: [String]]) -> Ancestry {
        var pid = process.ppid
        var visited: Set<Int32> = [process.pid]
        while pid > 1, !visited.contains(pid), let node = tree[pid] {
            visited.insert(pid)
            if let agent = agentName(node, arguments: arguments[pid] ?? []) {
                return .agentSpawned(agent: agent)
            }
            if let host = hostName(node) {
                return .attached(host: host)
            }
            pid = node.ppid
        }
        return .orphaned
    }

    static func agentName(_ node: ProcessNode, arguments: [String]) -> String? {
        let name = node.name.lowercased()
        if agentExecutables.contains(name) { return displayAgent(name) }
        for argument in arguments.prefix(3) {
            if argument.contains("@anthropic-ai/claude-code") || argument.contains("/claude-code/") { return "Claude Code" }
            if argument.contains("@openai/codex") { return "Codex" }
            if argument.contains("@google/gemini-cli") { return "Gemini CLI" }
        }
        return nil
    }

    static func displayAgent(_ executable: String) -> String {
        switch executable {
        case "claude": "Claude Code"
        case "codex": "Codex"
        case "gemini": "Gemini CLI"
        case "opencode": "opencode"
        default: executable
        }
    }

    static func hostName(_ node: ProcessNode) -> String? {
        if hostExecutables.contains(node.name.lowercased()) { return node.name }
        guard let bundle = ProcessGrouper.outermostAppBundle(in: node.executablePath) else { return nil }
        let app = ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
        return hostApps.contains(app.lowercased()) ? app : nil
    }
}

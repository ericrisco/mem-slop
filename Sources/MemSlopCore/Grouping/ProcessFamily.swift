import Foundation

/// A family of non-app processes that belong together in the UI (e.g. every Python interpreter).
public enum ProcessFamily: String, CaseIterable, Sendable, Codable {
    case agents
    case python
    case node
    case bun
    case deno
    case ruby
    case java
    case go
    case rust
    case php
    case databases
    case containers
    case shells

    public var displayName: String {
        switch self {
        case .agents: "AI Agents"
        case .python: "Python"
        case .node: "Node.js"
        case .bun: "Bun"
        case .deno: "Deno"
        case .ruby: "Ruby"
        case .java: "Java"
        case .go: "Go"
        case .rust: "Rust"
        case .php: "PHP"
        case .databases: "Databases"
        case .containers: "Containers"
        case .shells: "Shells"
        }
    }

    /// SF Symbol used when there is no app icon.
    public var symbolName: String {
        switch self {
        case .agents: "sparkles"
        case .python: "chevron.left.forwardslash.chevron.right"
        case .node, .bun, .deno: "hexagon"
        case .ruby: "diamond"
        case .java: "cup.and.saucer"
        case .go: "hare"
        case .rust: "gearshape.2"
        case .php: "curlybraces"
        case .databases: "cylinder.split.1x2"
        case .containers: "shippingbox"
        case .shells: "terminal"
        }
    }

    private static let executables: [ProcessFamily: Set<String>] = [
        .agents: ["claude", "codex", "gemini", "aider", "opencode", "amp", "cursor-agent", "goose", "crush", "qwen"],
        .python: ["uv", "uvx", "uvicorn", "gunicorn", "hypercorn", "daphne", "celery", "pip", "pip3", "jupyter",
                  "jupyter-lab", "jupyter-notebook", "ipython", "streamlit", "flask", "fastapi", "poetry", "pdm",
                  "hatch", "pytest", "mypy", "ruff", "pyright", "pylsp", "marimo"],
        .node: ["node", "npm", "npx", "pnpm", "yarn", "tsx", "ts-node", "next-server", "vite", "esbuild",
                "nodemon", "turbo", "webpack", "tsserver", "corepack"],
        .bun: ["bun", "bunx"],
        .deno: ["deno"],
        .ruby: ["ruby", "rails", "bundle", "puma", "irb", "rake", "sidekiq"],
        .java: ["java", "gradle", "mvn", "kotlin"],
        .go: ["go", "gopls", "air", "dlv"],
        .rust: ["cargo", "rustc", "rust-analyzer", "rustup"],
        .php: ["php", "php-fpm", "composer"],
        .databases: ["postgres", "postmaster", "mysqld", "mariadbd", "redis-server", "valkey-server", "mongod",
                     "clickhouse", "meilisearch", "qdrant", "ollama"],
        .containers: ["docker", "colima", "lima", "limactl", "qemu-system-aarch64", "qemu-system-x86_64",
                      "orbstack", "podman", "kubectl", "minikube", "kind"],
        .shells: ["zsh", "bash", "sh", "fish", "nu", "dash", "tmux", "screen", "login"],
    ]

    /// Argument fragments that reveal an agent CLI running inside a generic interpreter.
    static let agentArgumentMarkers = ["@anthropic-ai/claude-code", "@openai/codex", "@google/gemini-cli", "opencode-ai"]

    /// Classifies a process by executable name and arguments. Returns `nil` for anything else.
    public static func detect(name: String, arguments: [String]) -> ProcessFamily? {
        let lower = name.lowercased()
        if executables[.agents]!.contains(lower) { return .agents }
        if arguments.contains(where: { argument in agentArgumentMarkers.contains { argument.contains($0) } }) {
            return .agents
        }
        if lower.hasPrefix("python") || lower == "pythonw" { return .python }
        if lower.hasPrefix("ruby") { return .ruby }
        if lower.hasPrefix("php") { return .php }
        if lower.hasPrefix("com.docker") || lower.hasPrefix("com.apple.virtualization") { return .containers }
        for family in allCases where family != .agents {
            if executables[family]!.contains(lower) { return family }
        }
        return nil
    }
}

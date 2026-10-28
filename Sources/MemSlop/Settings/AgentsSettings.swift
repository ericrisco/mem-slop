import MemSlopCore
import SwiftUI

/// Installs the `memslop` command: a symlink to the binary inside the app bundle.
enum CommandLineTool {
    /// `MemSlop.app/Contents/Helpers/memslop`
    static var bundledPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/memslop").path
    }

    static var isBundled: Bool { FileManager.default.isExecutableFile(atPath: bundledPath) }

    /// Where `memslop` is linked, preferring a folder already on the default PATH.
    static var candidates: [String] {
        ["/usr/local/bin", "/opt/homebrew/bin", NSHomeDirectory() + "/.local/bin"]
    }

    /// The installed link (or file) named `memslop` that points at this app, if any.
    static var installedPath: String? {
        candidates.map { $0 + "/memslop" }.first { path in
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else {
                return FileManager.default.isExecutableFile(atPath: path)
            }
            return destination.hasSuffix("/Contents/Helpers/memslop")
        }
    }

    static func install() throws -> String {
        let fileManager = FileManager.default
        let home = NSHomeDirectory() + "/.local/bin"
        let directory = candidates.first { $0 != home && fileManager.isWritableFile(atPath: $0) } ?? home
        try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let link = directory + "/memslop"
        if (try? fileManager.destinationOfSymbolicLink(atPath: link)) != nil {
            try fileManager.removeItem(atPath: link)
        }
        try fileManager.createSymbolicLink(atPath: link, withDestinationPath: bundledPath)
        return link
    }

    static func uninstall() throws {
        guard let path = installedPath, (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil else { return }
        try FileManager.default.removeItem(atPath: path)
    }
}

struct AgentsSettings: View {
    @Environment(AppModel.self) private var model
    @State private var statuses: [AgentKind: HookInstaller.Status] = [:]
    @State private var cliPath = CommandLineTool.installedPath
    @State private var message: String?

    var body: some View {
        @Bindable var reaper = model.reaper
        Form {
            Section {
                Toggle(isOn: $reaper.configuration.cleanSessionLeftovers) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clean up when an agent session ends")
                        Text("What Claude Code, Codex or another agent left running is closed once idle for 5 minutes, even without a matching rule. Same warning and Keep button.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("MemSlop notices when an agent process exits. Connecting the hooks below also catches servers that were detached from the agent, the moment the session ends.")
                    .font(.caption).foregroundStyle(.secondary)
                if !reaper.leftovers.isEmpty {
                    Text("\(reaper.leftovers.count) leftover\(reaper.leftovers.count == 1 ? "" : "s") from ended sessions waiting to go idle")
                        .font(.caption).foregroundStyle(Theme.slop)
                }
            }

            Section("Session hooks") {
                ForEach(AgentKind.allCases, id: \.self) { agent in
                    HookRow(agent: agent, status: statuses[agent] ?? .notInstalled) { install in
                        toggleHook(agent, install: install)
                    }
                }
            }

            Section("Command line") {
                LabeledContent {
                    if cliPath != nil {
                        Button("Remove") { run { try CommandLineTool.uninstall() } }
                    } else {
                        Button("Install") { run { message = "Linked at \(try CommandLineTool.install())" } }
                            .disabled(!CommandLineTool.isBundled)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("memslop command")
                        Text(cliPath.map { "Installed at \($0)" } ?? "Use MemSlop from any terminal, and let your agents check ports before starting servers.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(verbatim: "memslop status · memslop ports · memslop ps --slop · memslop quit :3000")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
    }

    private func toggleHook(_ agent: AgentKind, install: Bool) {
        run {
            let installer = HookInstaller(agent: agent, executable: CommandLineTool.bundledPath)
            if install { try installer.install() } else { try installer.uninstall() }
            message = install ? "\(agent.displayName) connected. It applies to new sessions." : "\(agent.displayName) disconnected."
        }
    }

    private func run(_ action: () throws -> Void) {
        do { try action() } catch { message = "\(error)" }
        refresh()
    }

    private func refresh() {
        for agent in AgentKind.allCases {
            statuses[agent] = HookInstaller(agent: agent, executable: CommandLineTool.bundledPath).status()
        }
        cliPath = CommandLineTool.installedPath
    }
}

private struct HookRow: View {
    let agent: AgentKind
    let status: HookInstaller.Status
    let onChange: (Bool) -> Void

    var body: some View {
        LabeledContent {
            switch status {
            case .installed: Button("Disconnect") { onChange(false) }
            case .notInstalled: Button("Connect") { onChange(true) }.disabled(!CommandLineTool.isBundled)
            case .agentMissing: Text("Not installed").foregroundStyle(.tertiary)
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(status == .installed ? Theme.memory : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.displayName)
                    Text(status == .installed ? "Connected · SessionEnd hook in \(agent.settingsFile().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))" : "Adds one SessionEnd hook; your other settings stay as they are.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

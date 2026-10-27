import Foundation
import MemSlopCore

/// Synthetic but plausible data for `--demo`: screenshots and trying the UI without touching real processes.
enum DemoData {
    static let isEnabled = CommandLine.arguments.contains("--demo")

    /// PIDs far above anything real, and never signalled: the model refuses to quit in demo mode.
    private static let basePID: Int32 = 900_000

    private struct Spec {
        let name: String
        let path: String
        let arguments: [String]
        let memoryMB: Double
        let cpu: Double
        var ppid: Int32 = 1
    }

    private static let specs: [Spec] = {
        var specs: [Spec] = []
        func node(_ args: String, _ memory: Double, _ cpu: Double) {
            specs.append(Spec(name: "node", path: "/opt/homebrew/bin/node", arguments: ["node"] + args.split(separator: " ").map(String.init), memoryMB: memory, cpu: cpu))
        }
        node("/Users/dev/shop/node_modules/.bin/next dev --turbo", 1840, 0.1)
        node("/Users/dev/shop/node_modules/next/dist/server/lib/start-server.js", 1210, 0.0)
        node("/Users/dev/admin/node_modules/vite/bin/vite.js --port 5173", 620, 0.2)
        node("/Users/dev/api/node_modules/.bin/tsx watch src/index.ts", 410, 0.0)
        node("/Users/dev/docs/node_modules/.bin/astro dev", 380, 0.0)
        node("/Users/dev/shop/node_modules/.bin/vitest --watch", 940, 38)
        node("/opt/homebrew/lib/node_modules/typescript/lib/tsserver.js", 760, 3.2)
        for index in 0..<6 { node("/Users/dev/.npm/_npx/mcp-server-\(index)/index.js", 90 + Double(index * 12), 0.1) }
        specs.append(Spec(name: "claude", path: "/Users/dev/.local/bin/claude", arguments: ["claude"], memoryMB: 520, cpu: 4.1))
        specs.append(Spec(name: "claude", path: "/Users/dev/.local/bin/claude", arguments: ["claude", "--resume"], memoryMB: 410, cpu: 1.2))
        specs.append(Spec(name: "codex", path: "/opt/homebrew/bin/codex", arguments: ["codex"], memoryMB: 260, cpu: 0.8))
        specs.append(Spec(name: "python3.12", path: "/Users/dev/api/.venv/bin/python3.12", arguments: ["python3.12", "-m", "uvicorn", "main:app", "--reload"], memoryMB: 340, cpu: 0.0))
        specs.append(Spec(name: "python3.12", path: "/Users/dev/ml/.venv/bin/python3.12", arguments: ["python3.12", "-m", "ipykernel_launcher", "-f", "kernel.json"], memoryMB: 1460, cpu: 0.1))
        specs.append(Spec(name: "uv", path: "/opt/homebrew/bin/uv", arguments: ["uv", "run", "streamlit", "run", "app.py"], memoryMB: 290, cpu: 0.0))
        specs.append(Spec(name: "postgres", path: "/opt/homebrew/opt/postgresql@16/bin/postgres", arguments: ["postgres", "-D", "/opt/homebrew/var/postgresql@16"], memoryMB: 180, cpu: 0.3))
        specs.append(Spec(name: "redis-server", path: "/opt/homebrew/bin/redis-server", arguments: ["redis-server", "*:6379"], memoryMB: 24, cpu: 0.2))
        let chromeTest = "/Users/dev/Library/Caches/ms-playwright/chromium-1140/chrome-mac/Chromium.app/Contents/MacOS/Chromium"
        specs.append(Spec(name: "Chromium", path: chromeTest, arguments: ["Chromium", "--headless", "--remote-debugging-port=0"], memoryMB: 690, cpu: 0.0))
        let chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        specs.append(Spec(name: "Google Chrome", path: chrome, arguments: ["Google Chrome"], memoryMB: 420, cpu: 2.1))
        for index in 0..<14 {
            specs.append(Spec(name: "Google Chrome Helper (Renderer)",
                              path: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)",
                              arguments: ["Google Chrome Helper (Renderer)", "--type=renderer"], memoryMB: 80 + Double(index * 23), cpu: index == 2 ? 14 : 0.4))
        }
        for (app, memory, cpu) in [("Safari", 690.0, 1.4), ("Mail", 240.0, 0.3), ("Music", 180.0, 0.6), ("Notes", 120.0, 0.1), ("Calendar", 90.0, 0.0)] {
            let base = app == "Safari" ? "/Applications" : "/System/Applications"
            specs.append(Spec(name: app, path: "\(base)/\(app).app/Contents/MacOS/\(app)", arguments: [app], memoryMB: memory, cpu: cpu))
        }
        specs.append(Spec(name: "Xcode", path: "/Applications/Xcode.app/Contents/MacOS/Xcode", arguments: ["Xcode"], memoryMB: 2120, cpu: 6.5))
        specs.append(Spec(name: "SourceKitService", path: "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/sourcekitd.framework/SourceKitService", arguments: ["SourceKitService"], memoryMB: 980, cpu: 12))
        specs.append(Spec(name: "com.docker.backend", path: "/Applications/Docker.app/Contents/MacOS/com.docker.backend", arguments: ["com.docker.backend"], memoryMB: 1800, cpu: 3.0))
        for shell in 0..<4 { specs.append(Spec(name: "zsh", path: "/bin/zsh", arguments: ["-zsh"], memoryMB: 6 + Double(shell), cpu: 0)) }
        return specs
    }()

    private static let startTime = UInt64(Date().addingTimeInterval(-3 * 3600).timeIntervalSince1970 * 1_000_000)

    static func processes(at date: Date) -> [ProcessSample] {
        let phase = date.timeIntervalSince1970
        return specs.enumerated().map { index, spec in
            let wobble = 1 + 0.04 * sin(phase / 7 + Double(index))
            let cpu = max(0, spec.cpu * (spec.cpu > 1 ? (1 + 0.35 * sin(phase / 3 + Double(index))) : 1))
            return ProcessSample(
                id: ProcessIdentity(pid: basePID + Int32(index), startTime: startTime),
                ppid: spec.ppid, uid: getuid(), name: spec.name, executablePath: spec.path, arguments: spec.arguments,
                cpuPercent: cpu, memoryBytes: UInt64(spec.memoryMB * wobble * 1_048_576), cpuTimeNanos: 0,
                startDate: Date(timeIntervalSince1970: TimeInterval(startTime) / 1_000_000)
            )
        }
    }

    static func system(at date: Date) -> SystemSnapshot {
        let phase = date.timeIntervalSince1970
        let total: UInt64 = 32 * 1_073_741_824
        let used = UInt64(Double(total) * (0.71 + 0.02 * sin(phase / 11)))
        return SystemSnapshot(
            cpuUsage: 0.34 + 0.08 * sin(phase / 4), cpuUser: 0.24, cpuSystem: 0.10, coreCount: 12,
            memoryTotal: total, memoryUsed: used, memoryApp: used / 2, memoryWired: used / 5,
            memoryCompressed: 3 * 1_073_741_824, memoryCached: 4 * 1_073_741_824, swapUsed: 1_288_490_188,
            pressure: .normal, loadAverage: [4.12, 3.87, 3.51]
        )
    }

    /// 24 hours of believable history: a working day with spikes and a cleanup.
    static func history(now: Date) -> MetricHistory {
        var history = MetricHistory()
        let start = now.addingTimeInterval(-24 * 3600)
        for minute in 0..<(23 * 60) {
            let time = start.addingTimeInterval(TimeInterval(minute * 60))
            let hour = Calendar.current.component(.hour, from: time)
            let working = (9...20).contains(hour)
            let wave = sin(Double(minute) / 37) * 0.06 + sin(Double(minute) / 9) * 0.03
            let spike = (minute % 173 < 6 && working) ? 0.35 : 0
            let cpu = min(0.97, max(0.03, (working ? 0.28 : 0.07) + wave + spike))
            let creep = working ? Double(minute % 300) / 300 * 0.12 : 0
            let memory = min(0.95, max(0.3, (working ? 0.62 : 0.48) + creep + wave / 2))
            let top = [
                GroupUsage(name: "Node.js", cpuPercent: cpu * 300, memoryBytes: UInt64((4 + creep * 30) * 1_073_741_824)),
                GroupUsage(name: "Google Chrome", cpuPercent: 12, memoryBytes: 3_100_000_000),
                GroupUsage(name: "Xcode", cpuPercent: 8, memoryBytes: 3_000_000_000),
                GroupUsage(name: "Python", cpuPercent: 1, memoryBytes: 2_100_000_000),
            ]
            history.record(time: time, cpu: cpu, memory: memory, top: top)
            history.record(time: time.addingTimeInterval(30), cpu: cpu, memory: memory)
        }
        for second in stride(from: 3600, to: 0, by: -4) {
            let time = now.addingTimeInterval(-TimeInterval(second))
            let phase = time.timeIntervalSince1970
            history.record(time: time, cpu: 0.34 + 0.12 * sin(phase / 60) + 0.05 * sin(phase / 7), memory: 0.71 + 0.03 * sin(phase / 300))
        }
        return history
    }

    static func activity(now: Date) -> [ActivityEntry] {
        let rows: [(minutes: Double, name: String, group: String, rule: String, reason: String, mb: UInt64, command: String, outcome: ActivityEntry.Outcome)] = [
            (12, "node", "Node.js", "Next.js dev server", "started by Claude Code", 1_520, "node node_modules/.bin/next dev", .quit),
            (12, "Chromium", "Chromium", "Playwright browser", "orphaned", 840, "Chromium --headless --remote-debugging-port=0", .quit),
            (12, "python3.12", "Python", "Uvicorn", "started by Codex", 310, "python3.12 -m uvicorn main:app --reload", .forced),
            (73, "node", "Node.js", "Vite", "orphaned", 590, "node node_modules/vite/bin/vite.js", .quit),
            (73, "python3.12", "Python", "Jupyter kernel", "started by Claude Code", 1_380, "python3.12 -m ipykernel_launcher", .kept),
            (191, "node", "Node.js", "esbuild service", "started by Claude Code", 120, "esbuild --service=0.21.5 --ping", .quit),
            (240, "node", "Node.js", "Storybook", "orphaned", 760, "node node_modules/.bin/storybook dev -p 6006", .quit),
        ]
        return rows.enumerated().map { index, row in
            ActivityEntry(date: now.addingTimeInterval(-row.minutes * 60 - Double(index)), name: row.name, pid: 40_000 + Int32(index * 37),
                          group: row.group, rule: row.rule, reason: row.reason, memoryBytes: row.mb * 1_048_576,
                          commandLine: row.command, outcome: row.outcome)
        }
    }
}

/// Serves demo snapshots in place of the real sampler.
actor DemoSource: SnapshotSource {
    func sample(includeProcesses: Bool) -> MonitorSnapshot {
        let now = Date()
        let processes = DemoData.processes(at: now)
        var tree: [Int32: ProcessNode] = [1: ProcessNode(pid: 1, ppid: 0, name: "launchd", executablePath: "/sbin/launchd")]
        for process in processes {
            tree[process.pid] = ProcessNode(pid: process.pid, ppid: process.ppid, name: process.name, executablePath: process.executablePath)
        }
        return MonitorSnapshot(timestamp: now, system: DemoData.system(at: now), processes: processes, tree: tree)
    }
}

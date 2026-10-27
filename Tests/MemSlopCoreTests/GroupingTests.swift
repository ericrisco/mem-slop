import Testing
@testable import MemSlopCore

@Suite struct GroupingTests {
    @Test(arguments: [
        ("python3.12", ProcessFamily.python), ("Python", .python), ("uv", .python), ("uvicorn", .python),
        ("node", .node), ("next-server", .node), ("pnpm", .node), ("bun", .bun), ("claude", .agents),
        ("codex", .agents), ("postgres", .databases), ("zsh", .shells), ("cargo", .rust),
    ])
    func detectsFamily(name: String, family: ProcessFamily) {
        #expect(ProcessFamily.detect(name: name, arguments: [name]) == family)
    }

    @Test func detectsAgentRunningInNode() {
        let args = ["node", "/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js"]
        #expect(ProcessFamily.detect(name: "node", arguments: args) == .agents)
    }

    @Test func unknownIsNil() {
        #expect(ProcessFamily.detect(name: "Finder", arguments: []) == nil)
    }

    @Test func groupsUvPythonTogether() {
        let processes = [
            Fixture.process(name: "uv", arguments: ["uv", "run", "main.py"]),
            Fixture.process(name: "python3", arguments: ["python3", "main.py"]),
            Fixture.process(name: "python3.12", arguments: ["python3.12", "-m", "uvicorn"]),
        ]
        let groups = ProcessGrouper().group(processes, sortedBy: .cpu)
        #expect(groups.count == 1)
        #expect(groups[0].name == "Python")
        #expect(groups[0].processes.count == 3)
    }

    @Test func groupsAppHelpersUnderOutermostBundle() {
        let base = "/Applications/Google Chrome.app"
        let processes = [
            Fixture.process(name: "Google Chrome", path: "\(base)/Contents/MacOS/Google Chrome"),
            Fixture.process(
                name: "Google Chrome Helper (Renderer)",
                path: "\(base)/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
            ),
        ]
        let groups = ProcessGrouper().group(processes, sortedBy: .memory)
        #expect(groups.count == 1)
        #expect(groups[0].bundlePath == base)
        #expect(groups[0].processes.count == 2)
    }

    @Test func sortsGroupsByMemoryAndCPU() {
        let processes = [
            Fixture.process(name: "alpha", cpu: 80, memoryMB: 10),
            Fixture.process(name: "beta", cpu: 1, memoryMB: 900),
        ]
        #expect(ProcessGrouper().group(processes, sortedBy: .cpu).first?.name == "alpha")
        #expect(ProcessGrouper().group(processes, sortedBy: .memory).first?.name == "beta")
    }

    @Test func outermostBundle() {
        #expect(ProcessGrouper.outermostAppBundle(in: "/usr/bin/zsh") == nil)
        #expect(ProcessGrouper.outermostAppBundle(in: "/Applications/Foo.app/Contents/MacOS/Foo") == "/Applications/Foo.app")
    }
}

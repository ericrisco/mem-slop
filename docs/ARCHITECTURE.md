# Architecture

MemSlop is a Swift package with three targets: the app, the `memslop` command, and the shared core.

```
MemSlop.app (AppKit lifecycle, LSUIElement)
├── MemSlop          UI: status item, panel, dashboard, settings
│   ├── AppModel             @MainActor @Observable, the single source of truth
│   ├── MenuBar/             status item + indicator drawn with AppKit (6 styles)
│   ├── Panel/               popover: gauges, trend, reaper strip, grouped list
│   ├── Dashboard/           window: Overview · Processes · Activity · Rules
│   ├── Settings/            General · Auto-clean · Slop rules · Protected · About
│   ├── Reaper/              ReaperEngine (the cycle) + notifications
│   └── Demo/                synthetic data for --demo
├── MemSlopCLI       `memslop`, shipped as Contents/Helpers/memslop
└── MemSlopCore      no UI, fully unit-tested
    ├── Sampling/            Mach host stats, libproc, sysctl(KERN_PROC_ALL), ports, projects
    ├── Grouping/            app bundle → family → executable, or by project
    ├── Reaper/              rules, ancestry, idle tracker, policy, pressure trigger, agent sessions
    ├── Control/             SIGTERM → SIGKILL terminator
    ├── Integration/         Claude Code / Codex hook installer
    ├── History/             1 h fine + 24 h per-minute history
    └── Persistence/         activity log, savings, inbox, storage paths
```

## Sampling

- **System**: `host_statistics` for CPU ticks, `host_statistics64` for VM pages (memory used =
  app + wired + compressed, like Activity Monitor), `kern.memorystatus_vm_pressure_level`,
  `vm.swapusage`, `getloadavg`.
- **Processes**: `sysctl(KERN_PROC_ALL)` lists every process, including root-owned ones, so the
  parent chain can be walked through `login`. For the user's own processes, `proc_pid_rusage`
  (v4) gives CPU time and physical footprint. CPU time comes in Mach ticks on Apple Silicon and
  is converted with `mach_timebase_info`. Command lines (`KERN_PROCARGS2`) and paths are cached
  per process identity.
- **Context**: while a list is visible, `proc_pidinfo(PROC_PIDLISTFDS)` + `PROC_PIDFDSOCKETINFO`
  give listening TCP ports and `PROC_PIDVNODEPATHINFO` the working directory, at most every 15 s
  per process (about 6 ms for 700 processes). `ProjectResolver` walks up to the nearest `.git` or
  manifest and ignores system and app-data folders.
- **Session tag**: the environment block of `KERN_PROCARGS2` is scanned once per process for
  `CLAUDE_CODE_SESSION_ID`, which Claude Code sets in every Bash command and children inherit.
  macOS hides the environment of Apple platform binaries, not of node, python or other dev servers.
- **Identity** is `(pid, start time)`, so a recycled PID never inherits history or a Keep.
- The sampler runs on an actor every 2 s. The process table refreshes every tick while a list is
  visible and every 10 s otherwise.

## Auto-clean

`ReaperPolicy` is a pure function from a snapshot, an `IdleTracker` and the configuration to a list
of candidates. Every acceptance criterion of the auto-reaper spec has a unit test.
`ReaperEngine` runs the cycle on the main actor: sweep, then announce, then a grace period, then
re-check and close, then log. Before closing, it re-runs the policy and spares any process that
burned more than 50 ms of CPU or changed memory during the grace period.

`IdleTracker` keeps a checkpoint every 30 s per process. A gap of more than 2 minutes (sleep, app
paused) resets that process's history.

Two triggers run a sweep early, with a shorter idle window (5 min, or the interval if shorter):
`PressureTrigger` after 30 s of critical memory pressure (at most every 5 min), and session
leftovers, checked every 30 s.

## Agent sessions

A *session leftover* is a process started by an agent session that has ended. Leftovers need no
slop rule, but every other safeguard applies. They come from two sources:

- **Agent exit** (`AgentSessionTracker`, no setup): the app remembers which agent each process
  descends from. When that agent's process disappears, its surviving descendants are leftovers.
- **SessionEnd hook** (`memslop hooks install`): Claude Code and Codex run
  `memslop hook session-end`, which walks up to the agent, collects its descendants and every
  process tagged with the session ID (this finds servers detached to `launchd`), and drops an
  event in the inbox. `/clear` and `/resume` are ignored: the agent keeps running.

The command and the app never share a file. The command writes one JSON file per event to
`~/Library/Application Support/MemSlop/inbox/`. The app drains it on its next process sample:
session leftovers, plus activity from `memslop quit` so it counts towards memory freed.
`MEMSLOP_DATA_DIR` moves all data elsewhere for tests.

## Performance notes

- The menu bar image is drawn with AppKit, not `ImageRenderer`. The renderer allocated about
  100 MB per frame.
- Rules are compiled once per configuration. Command lines are matched as lowercased bytes with
  `memmem`, and each process's match is cached for its lifetime.
- No implicit SwiftUI animations run on values that change every tick.
- Charts downsample to at most 240 points.

## Design records

The specs, plan and decisions behind each version are kept in the maintainer's SDD wiki. The
CHANGELOG summarises what each one shipped.

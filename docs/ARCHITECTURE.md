# Architecture

MemSlop is a Swift package with two targets.

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
└── MemSlopCore      no UI, fully unit-tested
    ├── Sampling/            Mach host stats, libproc, sysctl(KERN_PROC_ALL)
    ├── Grouping/            app bundle → family → executable
    ├── Reaper/              rules, ancestry, idle tracker, policy
    ├── Control/             SIGTERM → SIGKILL terminator
    ├── History/             1 h fine + 24 h per-minute history
    └── Persistence/         activity log, storage paths
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

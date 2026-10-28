# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [1.3.0] - 2026-10-28

### Added
- **Automatic updates**: a daily check of the latest GitHub release. Updates are downloaded, verified (SHA-256, bundle identifier, version, code signature), installed in place and relaunched. Both checking and installing can be turned off in Settings → General → Updates, with *Check Now* and release notes. Automatic installs wait for any pending cleanup warning.
- **Homebrew cask**: `brew tap ericrisco/memslop https://github.com/ericrisco/mem-slop && brew install --cask memslop`. It links the `memslop` command. Releases bump the cask automatically.
- An "Update" button in the panel when automatic install is off.

### Changed
- Privacy: the update check is MemSlop's only network request.

## [1.2.0] - 2026-10-28

### Added
- **`memslop` command**, bundled in the app and linked by the installer (or Settings → Agents): `status`, `ps [--slop] [--json]`, `ports [--json]`, `quit <pid|:port> [--yes]`, `hooks install|uninstall|status`. Closes from the terminal are logged and count towards memory freed.
- **Session-end cleanup** (on by default): what an ended agent session left running is closed once idle for 5 minutes, without needing a slop rule, with the usual warning, Keep and re-check.
  - Works with no setup by noticing the agent process exit (Claude Code, Codex, Gemini CLI and others).
  - **Session hooks** for Claude Code and Codex (`memslop hooks install`, or Settings → Agents → Connect) also find servers that were detached from the agent, through the session ID Claude Code puts in their environment. `/clear` and `/resume` are ignored.
- Settings → **Agents** tab: session cleanup toggle, hook status with Connect/Disconnect, command line install.
- `MEMSLOP_DATA_DIR` to keep data elsewhere (tests, development).

### Changed
- Pressure sweeps no longer move the regular schedule.

## [1.1.0] - 2026-10-28

### Added
- **Ports and projects** in the process list: each process shows the TCP ports it listens on and the project folder it runs in (nearest folder with `.git` or a package manifest). Groups show the union of their ports.
- **Group by project**: a toggle next to the sort control groups processes by repository instead of by kind. The choice is remembered.
- Search also matches ports (`3000`, `:3000`) and project names.
- **Clean early when memory is critical** (on by default): after 30 s of critical memory pressure, auto-clean checks right away and accepts processes idle for 5 minutes, at most once every 5 minutes. Same rules, warning and Keep button.
- **Memory freed** pill in the panel header, and the total since install in the dashboard. Processes quit by hand are now written to the activity log as *Manual* and count too.

### Changed
- Ports and folders are read only while the list or dashboard is open, at most every 15 s per process.
- Saved auto-clean settings from older versions load with new options at their defaults instead of being reset.

## [1.0.0] - 2026-10-27

### Added
- One-line installer (`install.sh`): downloads the latest release, verifies its SHA-256, installs and opens MemSlop. Also supports `--version`, `--from-source`, `--dir`, `--no-launch` and `--uninstall`.
- Universal (Apple Silicon + Intel) releases built and published by GitHub Actions on every tag, with notes taken from this changelog.
- CI on every push and pull request: build with warnings as errors, tests, app bundle and ShellCheck.
- App icon: a memory chip melting into slop.
- `--demo` mode with synthetic data, for trying the UI and taking screenshots without touching real processes.
- README, architecture notes and contributing guide.

### Fixed
- History stays ordered if the system clock goes backwards.

## [0.3.0] - 2026-10-27

### Added
- **Dashboard window** with a sidebar: Overview, Processes, Activity and Rules.
- 24-hour CPU and memory history that survives restarts, with 1 h / 6 h / 24 h charts. Hover any moment to see what was using the most memory then.
- Overview cards for CPU, memory, pressure and load, the biggest groups right now, and an auto-clean summary (memory freed today).
- Activity table of everything auto-clean closed, kept or would have closed, with filters and search.
- "Open Dashboard" in the panel, the panel menu and the right-click menu.

### Changed
- Much cheaper rule matching (byte-level search, rules compiled once, results cached per process). The dashboard stays at a few percent of one core.

## [0.2.0] - 2026-10-27

### Added
- **Auto-clean**: every 10, 15, 20, 30 or 60 minutes, closes idle dev slop. That means dev servers (Next.js, Vite, uvicorn, Flask, Django, Streamlit, Jupyter…), test browsers (Chrome for Testing, Playwright, Puppeteer, headless) and leftovers from AI agents.
- Safety rules: a process is only closed when it matches a slop rule, is not protected, is not a regular app, is not attached to a terminal or IDE (unless an AI agent such as Claude Code or Codex started it), and it and its children were idle for the whole interval.
- 60-second warning with **Keep** and **Close now**, in the panel and as a notification. A process that wakes up during the warning is spared.
- Dry-run mode that only logs what would be closed.
- Settings window: menu bar style, refresh rate, open at login, auto-clean options, and editors for slop rules and the protected list (with a live "running" count per rule).
- "Slop" badges on processes and groups that match a rule.
- Activity log of every close, kept for 24 hours.

## [0.1.0] - 2026-10-27

### Added
- Menu bar indicator with CPU and RAM usage and six styles: CPU and RAM, stacked, mini bars, CPU only, RAM only, icon only.
- Panel with CPU and RAM gauges, memory used, memory pressure, load average, swap and a live trend.
- Process list grouped by app bundle (all Chrome helpers under Google Chrome) or by family (Python/uv, Node.js, AI agents, databases…).
- Sort by CPU or memory, search by name, PID or command.
- Quit a process, a whole group, or a multi-selection. Apps are asked to quit like the Dock does; other processes get SIGTERM, then SIGKILL after 5 s.
- Core sampling with libproc and Mach (under 1% CPU and ~20 MB while idle).

[1.3.0]: https://github.com/ericrisco/mem-slop/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/ericrisco/mem-slop/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/ericrisco/mem-slop/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/ericrisco/mem-slop/releases/tag/v1.0.0
[0.3.0]: https://github.com/ericrisco/mem-slop/releases/tag/v0.3.0
[0.2.0]: https://github.com/ericrisco/mem-slop/releases/tag/v0.2.0
[0.1.0]: https://github.com/ericrisco/mem-slop/releases/tag/v0.1.0

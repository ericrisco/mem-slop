# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

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

# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-10-27

### Added
- Menu bar indicator with CPU and RAM usage and six styles: CPU and RAM, stacked, mini bars, CPU only, RAM only, icon only.
- Panel with CPU and RAM gauges, memory used, memory pressure, load average, swap and a live trend.
- Process list grouped by app bundle (all Chrome helpers under Google Chrome) or by family (Python/uv, Node.js, AI agents, databases…).
- Sort by CPU or memory, search by name, PID or command.
- Quit a process, a whole group, or a multi-selection. Apps are asked to quit like the Dock does; other processes get SIGTERM, then SIGKILL after 5 s.
- Core sampling with libproc and Mach (under 1% CPU and ~20 MB while idle).

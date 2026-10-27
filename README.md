# mem-slop

**Your AI agents leave slop running. MemSlop cleans it up.**

MemSlop is a native macOS menu bar app that shows CPU and RAM at a glance and lets you kill
what is eating your Mac, grouped the way you think about it: *all the Python servers*, *all of
Chrome*, *everything Claude Code left behind*.

> Status: early development. See the [CHANGELOG](CHANGELOG.md).

## Features

- CPU and RAM percentage in the menu bar, in six styles.
- One click opens a panel with gauges, memory pressure, load average and a live trend.
- Processes grouped by app or family (Python/uv, Node.js, AI agents, databases…), sortable by
  CPU or memory, searchable.
- Quit one process, a group, or a selection. Apps quit politely; stubborn processes get forced.
- **Auto-clean** of idle dev slop every 10 minutes (configurable), with a 60 s warning and a Keep
  button. It never touches your apps, or a server you started in your own terminal.

## Build from source

Requirements: macOS 14+, Xcode 16+ (Swift 6).

```bash
git clone https://github.com/ericrisco/mem-slop.git
cd mem-slop
make install     # builds MemSlop.app and copies it to /Applications
```

Other targets: `make test`, `make run`, `make uninstall`.

## License

[MIT](LICENSE)

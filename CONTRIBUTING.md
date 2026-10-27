# Contributing

Thanks for helping clean up the slop.

## Setup

- macOS 14+, Xcode 16+ (Swift 6).
- `make test` runs the unit tests. `make run` builds and opens the app. `make demo` opens it with
  fake data, which is handy for UI work and screenshots.

## Guidelines

- **Decisions go in `MemSlopCore`, with tests.** Matching, grouping, idleness, ancestry and the
  reaper policy are pure and covered by Swift Testing. The UI layer stays thin.
- **Safety first.** Auto-clean must never close something the user is using. A change that widens
  what can be closed needs a test that shows what stays protected.
- **Stay light.** MemSlop must sit under 1% CPU with the panel closed. Measure with
  `top -pid $(pgrep -x MemSlop)` before and after UI changes.
- **No dependencies, no network.**
- **English** in code, UI and docs. [Conventional Commits](https://www.conventionalcommits.org/).
- Run `make verify` before opening a pull request. CI runs the same checks.

## Adding a default slop rule

Add it to `ProcessRule.defaultSlop` in `Sources/MemSlopCore/Reaper/ProcessRule.swift` and add a
case to `ReaperTests`. Prefer command fragments that only appear in dev tooling (`next dev`, not
`node`).

## Releasing

1. Update `VERSION` and add a section to `CHANGELOG.md`.
2. Commit, then `git tag -a vX.Y.Z -m "MemSlop X.Y.Z" && git push --tags`.
3. The Release workflow builds the universal app, publishes `MemSlop.zip` with its checksum and
   uses the CHANGELOG section as the release notes.

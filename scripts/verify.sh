#!/usr/bin/env bash
# Verification gate: build, test and bundle the app. Fails on the first error.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> swift build (debug, warnings as errors in Core)"
swift build -Xswiftc -warnings-as-errors 2>&1 | tail -3

echo "==> swift test"
swift test 2>&1 | grep -E "Test run|passed|failed|error" | tail -5

echo "==> app bundle"
./scripts/build-app.sh >/dev/null
test -x dist/MemSlop.app/Contents/MacOS/MemSlop
echo "==> verify OK"

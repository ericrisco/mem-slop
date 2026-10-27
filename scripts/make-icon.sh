#!/usr/bin/env bash
# Regenerates Resources/AppIcon.icns from scripts/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

swift scripts/make-icon.swift "$work/icon.png" >/dev/null
iconset="$work/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$work/icon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$work/icon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o Resources/AppIcon.icns
cp "$work/icon.png" docs/assets/icon.png 2>/dev/null || { mkdir -p docs/assets && cp "$work/icon.png" docs/assets/icon.png; }
echo "==> Resources/AppIcon.icns"

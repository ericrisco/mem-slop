#!/usr/bin/env bash
# Zips dist/MemSlop.app into release archives with SHA-256 checksums.
set -euo pipefail
cd "$(dirname "$0")/../dist"

version="$(tr -d '[:space:]' < ../VERSION)"
[ -d MemSlop.app ] || { echo "dist/MemSlop.app not found; run scripts/build-app.sh first" >&2; exit 1; }

rm -f MemSlop.zip MemSlop.zip.sha256 "MemSlop-${version}.zip" checksums.txt
ditto -c -k --keepParent MemSlop.app MemSlop.zip
cp MemSlop.zip "MemSlop-${version}.zip"
shasum -a 256 MemSlop.zip > MemSlop.zip.sha256
shasum -a 256 MemSlop.zip "MemSlop-${version}.zip" > checksums.txt
cat checksums.txt

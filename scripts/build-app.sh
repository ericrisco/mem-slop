#!/usr/bin/env bash
# Builds MemSlop.app into dist/ (universal binary when --universal is passed).
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP="dist/MemSlop.app"

ARCH_FLAGS=()
if [[ "${1:-}" == "--universal" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "==> Building MemSlop ${VERSION} (${BUILD})"
swift build -c release --product MemSlop "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}"
swift build -c release --product memslop-cli "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}"
BIN_DIR="$(swift build -c release --product MemSlop "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}" --show-bin-path)"

echo "==> Assembling ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources" "${APP}/Contents/Helpers"
cp "${BIN_DIR}/MemSlop" "${APP}/Contents/MacOS/MemSlop"
# The `memslop` command; Helpers/ keeps it apart from MacOS/MemSlop on case-insensitive disks.
cp "${BIN_DIR}/memslop-cli" "${APP}/Contents/Helpers/memslop"
sed -e "s/__VERSION__/${VERSION}/" -e "s/__BUILD__/${BUILD}/" Resources/Info.plist > "${APP}/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "${APP}/Contents/Resources/AppIcon.icns"
fi

echo "==> Signing (ad-hoc)"
codesign --force --deep --options runtime --sign - "${APP}"
codesign --verify --strict "${APP}"
echo "==> Done: ${APP}"

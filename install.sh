#!/usr/bin/env bash
# MemSlop installer.
#
#   curl -fsSL https://raw.githubusercontent.com/ericrisco/mem-slop/main/install.sh | bash
#
# Options (pass after `bash -s --` when piping):
#   --version X.Y.Z   install a specific release instead of the latest
#   --from-source     build from source with Swift instead of downloading
#   --dir DIR         install into DIR (default: /Applications, or ~/Applications if not writable)
#   --no-launch       do not open MemSlop after installing
#   --uninstall       remove MemSlop, its settings and its data
#
# Written for the bash 3.2 that ships with macOS.
set -euo pipefail
IFS=$'\n\t'

readonly REPO="${MEMSLOP_REPO:-ericrisco/mem-slop}"
readonly APP_NAME="MemSlop.app"
readonly BUNDLE_ID="com.ericrisco.memslop"
readonly MIN_MACOS_MAJOR=14

version=""
from_source=0
launch=1
uninstall=0
install_dir=""

say() { printf '\033[1;35m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,16p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//' || true
}

while [ $# -gt 0 ]; do
  case "$1" in
    --version) version="${2:?--version needs a value, e.g. 1.0.0}"; version="${version#v}"; shift 2 ;;
    --from-source) from_source=1; shift ;;
    --dir) install_dir="${2:?--dir needs a path}"; shift 2 ;;
    --no-launch) launch=0; shift ;;
    --uninstall) uninstall=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
done

[ "$(uname -s)" = "Darwin" ] || die "MemSlop only runs on macOS."
macos_major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$macos_major" -ge "$MIN_MACOS_MAJOR" ] || die "MemSlop needs macOS ${MIN_MACOS_MAJOR} or later (you have $(sw_vers -productVersion))."

if [ -z "$install_dir" ]; then
  if [ -w /Applications ]; then install_dir="/Applications"; else install_dir="$HOME/Applications"; fi
fi
target="${install_dir%/}/${APP_NAME}"

quit_running() {
  if pgrep -x MemSlop >/dev/null 2>&1; then
    say "Quitting the running MemSlop"
    osascript -e "tell application id \"${BUNDLE_ID}\" to quit" >/dev/null 2>&1 || pkill -x MemSlop || true
    sleep 1
  fi
}

if [ "$uninstall" -eq 1 ]; then
  quit_running
  for dir in /Applications "$HOME/Applications"; do
    if [ -d "${dir}/${APP_NAME}" ]; then
      say "Removing ${dir}/${APP_NAME}"
      rm -rf "${dir:?}/${APP_NAME}"
    fi
  done
  rm -rf "${HOME:?}/Library/Application Support/MemSlop"
  defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
  say "MemSlop uninstalled."
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [ "$from_source" -eq 1 ]; then
  command -v swift >/dev/null 2>&1 || die "Swift not found. Install Xcode 16+ or the Command Line Tools, or drop --from-source."
  command -v git >/dev/null 2>&1 || die "git not found."
  ref="main"
  [ -n "$version" ] && ref="v${version}"
  say "Cloning ${REPO} (${ref})"
  git clone --quiet --depth 1 --branch "$ref" "https://github.com/${REPO}.git" "$tmp/src"
  say "Building (this takes a minute)"
  (cd "$tmp/src" && ./scripts/build-app.sh >/dev/null)
  built="$tmp/src/dist/${APP_NAME}"
else
  if [ -n "$version" ]; then
    base="https://github.com/${REPO}/releases/download/v${version}"
  else
    base="https://github.com/${REPO}/releases/latest/download"
  fi
  say "Downloading MemSlop${version:+ ${version}}"
  curl -fsSL --retry 3 "${base}/MemSlop.zip" -o "$tmp/MemSlop.zip" \
    || die "download failed: ${base}/MemSlop.zip (is there a release? try --from-source)"
  curl -fsSL --retry 3 "${base}/MemSlop.zip.sha256" -o "$tmp/MemSlop.zip.sha256" \
    || die "could not download the checksum"
  expected="$(awk '{print $1}' "$tmp/MemSlop.zip.sha256")"
  actual="$(shasum -a 256 "$tmp/MemSlop.zip" | awk '{print $1}')"
  if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
    die "checksum mismatch (expected ${expected:-nothing}, got ${actual}). Nothing was installed."
  fi
  say "Checksum OK"
  ditto -x -k "$tmp/MemSlop.zip" "$tmp/unzipped"
  built="$tmp/unzipped/${APP_NAME}"
fi

[ -d "$built" ] || die "build output not found: $built"

quit_running
mkdir -p "$install_dir"
if [ -d "$target" ]; then
  say "Replacing ${target}"
  rm -rf "${target:?}"
else
  say "Installing to ${target}"
fi
ditto "$built" "$target"
# Downloaded apps carry a quarantine flag; MemSlop is ad-hoc signed, not notarized.
xattr -dr com.apple.quarantine "$target" 2>/dev/null || true

installed_version="$(defaults read "${target}/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?")"
say "MemSlop ${installed_version} installed."

if [ "$launch" -eq 1 ]; then
  open "$target"
  say "Look for it in your menu bar. Auto-clean starts after a full interval (10 min by default)."
fi

#!/usr/bin/env bash
# Live check of ScreenMate's engine against a real Mac (macOS only).
#
#   bash Tools/run-probe.sh                      # this Mac via 127.0.0.1, user = $USER
#   bash Tools/run-probe.sh --host 192.0.2.10 --user your-mac-user --snapshots
#
# The Mac account password is asked for in the terminal with echo off. It is
# never passed as an argument, printed, or written to disk.
# --snapshots saves desktop-all.png and monitor-N.png (crops of the received
# combined desktop) under ProbeResults/<time>/ to check monitor selection.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEV="${DEVELOPER_DIR:-/Applications/Develop/Xcode-beta.app/Contents/Developer}"
if [[ ! -d "$DEV" ]]; then
  DEV="$(xcode-select -p)"
fi
export DEVELOPER_DIR="$DEV"

ARGS=()
SNAP=""
for arg in "$@"; do
  if [[ "$arg" == "--snapshots" ]]; then
    SNAP="$ROOT/ProbeResults/$(date +%Y%m%d-%H%M%S)"
  else
    ARGS+=("$arg")
  fi
done
if [[ -n "$SNAP" ]]; then
  ARGS+=("--snapshots" "$SNAP")
fi

echo "Building screenmate-probe (first run fetches packages)…"
swift build --package-path "$ROOT/Packages/ScreenMateKit" \
  --scratch-path "$ROOT/.build/probe" \
  --product screenmate-probe -c release 2>&1 | tail -n 2

"$ROOT/.build/probe/release/screenmate-probe" "${ARGS[@]+"${ARGS[@]}"}" 2>&1 | tee "$ROOT/.build/probe/last-run.txt"

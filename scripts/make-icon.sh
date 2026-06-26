#!/usr/bin/env bash
# Regenerates Resources/AppIcon.icns from the SF Symbols thermometer.
# Run via `make icon`. Requires the Xcode command-line tools (swift, sips,
# iconutil) — macOS only. The resulting .icns is committed, so a normal
# `make gui` build does NOT need to run this.
set -euo pipefail

cd "$(dirname "$0")/.."
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

png="$work/icon_1024.png"
swift scripts/AppIconGen.swift "$png"

set="$work/AppIcon.iconset"
mkdir -p "$set"
for s in 16 32 128 256 512; do
    sips -z "$s" "$s"           "$png" --out "$set/icon_${s}x${s}.png"    >/dev/null
    sips -z "$((s*2))" "$((s*2))" "$png" --out "$set/icon_${s}x${s}@2x.png" >/dev/null
done

mkdir -p Resources
iconutil -c icns "$set" -o Resources/AppIcon.icns
echo "wrote Resources/AppIcon.icns"

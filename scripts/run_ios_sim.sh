#!/usr/bin/env bash
# Builds the iPhone and iPad app, boots a simulator, opens it on screen and launches the app there.
#
# Usage: scripts/run_ios_sim.sh [--demo] [--open-only] ["<simulator name>"]
#   --demo        a fresh temporary library with the demo notes (nothing in the simulator's own library changes)
#   --open-only   only boot the simulator and show it; no build
#   name          default: FEATHER_SIM, else "iPhone 18 Pro"; e.g. "iPad Pro 13-inch (M5)"
# The simulator shows in Device Hub (Xcode 27 replaced Simulator.app with it) or, on older Xcode, Simulator.app.
# The build goes to build/sim-run; its log to build/sim-run.log.
set -euo pipefail
cd "$(dirname "$0")/.."

demo=0
open_only=0
name="${FEATHER_SIM:-iPhone 18 Pro}"
for arg in "$@"; do
  case "$arg" in
    --demo) demo=1 ;;
    --open-only) open_only=1 ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) name="$arg" ;;
  esac
done

udid=$(xcrun simctl list devices available | grep -F "    $name (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)
if [ -z "$udid" ]; then
  echo "no available simulator named \"$name\". These are:" >&2
  xcrun simctl list devices available | grep -E "iPhone|iPad" >&2
  exit 1
fi

echo "simulator: $name ($udid)"
xcrun simctl boot "$udid" 2>/dev/null || true   # already booted is fine

developer=$(xcode-select -p)
viewer=""
for app in "$developer/../Applications/DeviceHub.app" "$developer/Applications/Simulator.app"; do
  if [ -d "$app" ]; then viewer="$app"; break; fi
done
if [ -n "$viewer" ]; then open "$viewer"; else echo "no Device Hub or Simulator.app in $developer: the simulator runs without a window" >&2; fi

[ "$open_only" = 1 ] && exit 0

[ -d FeatherNote.xcodeproj ] || xcodegen generate
echo "building FeatherMarkiOS (log: build/sim-run.log)…"
mkdir -p build
if ! xcodebuild build -project FeatherNote.xcodeproj -scheme FeatherMarkiOS -destination "id=$udid" -derivedDataPath build/sim-run > build/sim-run.log 2>&1; then
  grep -E "error:|\*\* BUILD FAILED" build/sim-run.log | head -20 >&2
  echo "build failed: see build/sim-run.log" >&2
  exit 1
fi
xattr -w com.dropbox.ignored 1 build 2>/dev/null || true

app="build/sim-run/Build/Products/Debug-iphonesimulator/FeatherMark.app"
bundle=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")
xcrun simctl bootstatus "$udid" > /dev/null
xcrun simctl install "$udid" "$app"
xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
if [ "$demo" = 1 ]; then
  xcrun simctl launch "$udid" "$bundle" -FeatherTemporaryLibrary -FeatherSeedDemo > /dev/null
  echo "FeatherMark is running on $name with the demo notes"
else
  xcrun simctl launch "$udid" "$bundle" > /dev/null
  echo "FeatherMark is running on $name"
fi

#!/usr/bin/env bash
# Prints an xcodebuild destination on an iOS 18.x simulator runtime (the app's minimum), creating a
# "FeatherMark iOS 18" iPhone there once if none exists. Prints nothing and exits 1 when no iOS 18 runtime is
# installed (Xcode 27 can't download one: install it from developer.apple.com, then `xcrun simctl runtime add <dmg>`).
set -uo pipefail

runtime=$(xcrun simctl list runtimes | sed -nE 's/^iOS 18\.[0-9.]+ .* - (com\.apple\.CoreSimulator\.SimRuntime\.iOS-18-[0-9-]+).*/\1/p' | tail -n 1)
[ -n "$runtime" ] || exit 1

name="FeatherMark iOS 18"
udid=$(xcrun simctl list devices "$runtime" | sed -nE "s/^ +$name \(([0-9A-F-]+)\).*/\1/p" | head -n 1)
if [ -z "$udid" ]; then
  # The newest iPhone the runtime supports.
  type=$(xcrun simctl list devicetypes | sed -nE 's/^(iPhone 16( Pro)?) \((com\.apple\.CoreSimulator\.SimDeviceType\.[^)]+)\).*/\3/p' | head -n 1)
  [ -n "$type" ] || exit 1
  udid=$(xcrun simctl create "$name" "$type" "$runtime") || exit 1
fi
echo "platform=iOS Simulator,id=$udid"

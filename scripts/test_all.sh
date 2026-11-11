#!/usr/bin/env bash
# Every check for the Apple repo, macOS and iOS: the local stand-in for "CI green" (../AGENTS.md "GitHub Actions").
# Runs, in order, and stops at the first failure, naming it:
#   1. scripts/check_paths.sh
#   2. swift test for every package (macOS)
#   3. the shared packages' tests on an iOS simulator (scripts/test_ios_packages.sh)
#   4. the Mac app's full test scheme (app, packages, UI tests)
#   5. the iPhone and iPad app's tests (unit and UI) on the first available iPhone and iPad simulators
#   6. iOS 18, the app's minimum: the shared packages and the iOS app on an iOS 18 simulator, when that runtime
#      is installed (scripts/ios18_destination.sh); otherwise it says so and skips
# Prints "all tests: OK" only when every step passed. Logs go to $TMPDIR/feathermark-all-tests/.
set -uo pipefail
cd "$(dirname "$0")/.."
logs="${TMPDIR:-/tmp}/feathermark-all-tests"
mkdir -p "$logs"

fail() { echo "FAILED: $1${2:+ (log: $2)}" >&2; exit 1; }

# Runs the iOS app's tests on one destination. xcodebuild can hang (after a failing UI test, or booting or
# installing on a simulator), so ten minutes without new output stops it, from the start of the build; only
# "** TEST SUCCEEDED **" with no failed case passes.
run_ios_app() {   # destination, log
  xcodebuild test -project FeatherNote.xcodeproj -scheme FeatherMarkiOS -destination "$1" > "$2" 2>&1 &
  local pid=$! idle=0 size=0 now
  while kill -0 "$pid" 2>/dev/null; do
    now=$(stat -f %z "$2" 2>/dev/null || echo 0)
    if [ "$now" = "$size" ]; then idle=$((idle + 1)); else idle=0; size=$now; fi
    if [ "$idle" -ge "${FEATHER_IOS_IDLE_LIMIT:-600}" ]; then echo "  (xcodebuild was silent for 10 minutes; stopped it)" >&2; kill "$pid" 2>/dev/null; break; fi
    sleep 1
  done
  wait "$pid" 2>/dev/null
  grep -q '\*\* TEST SUCCEEDED \*\*' "$2" && ! grep -qE "Test Case .* failed" "$2"
}

# The first available simulator whose name starts with $1 (iPhone, iPad), as "<udid> <name>". Names can hold
# parentheses ("iPad Pro 13-inch (M5)"), so the device is addressed by its id.
first_simulator() {
  xcrun simctl list devices available | sed -nE "s/^ +($1.*) \(([0-9A-F-]{36})\) \(.*/\2 \1/p" | head -n 1
}

echo "step 1: paths"
bash scripts/check_paths.sh || fail "scripts/check_paths.sh"

echo "step 2: packages on macOS"
for package in FeatherCore FeatherCrypto FeatherSync FeatherEditor FeatherImport FeatherAppModel; do
  filter=()
  # The two-device tests need the local server (AGENTS.md "FeatherSync and Feather Cloud").
  [ "$package" = FeatherSync ] && filter=(--filter FeatherSyncTests)
  log="$logs/macos-$package.log"
  swift test --package-path "Packages/$package" ${filter[@]+"${filter[@]}"} > "$log" 2>&1 || fail "swift test for $package" "$log"
  grep -E '^✔ Test run with' "$log" | sed "s/^/  $package: /"
done

echo "step 3: shared packages on iOS"
bash scripts/test_ios_packages.sh || fail "iOS package tests (scripts/test_ios_packages.sh)"

echo "step 4: the Mac app"
# The Mac UI tests wait on the screen with short timeouts: shut the iOS simulators down first so they don't
# compete for the machine (step 5 boots what it needs).
xcrun simctl shutdown all > /dev/null 2>&1 || true
log="$logs/macos-app.log"
{ xcodegen generate && xcodebuild test -project FeatherNote.xcodeproj -scheme FeatherNote -destination 'platform=macOS'; } > "$log" 2>&1 || fail "the Mac app's xcodebuild test" "$log"
grep -q '\*\* TEST SUCCEEDED \*\*' "$log" || fail "the Mac app's xcodebuild test" "$log"

echo "step 5: the iPhone and iPad app"
for kind in iPhone iPad; do
  device=$(first_simulator "$kind")
  [ -n "$device" ] || fail "no $kind simulator (xcodebuild -downloadPlatform iOS)"
  name=${device#* }
  log="$logs/ios-app-$kind.log"
  run_ios_app "platform=iOS Simulator,id=${device%% *}" "$log" || fail "the iOS app's tests on $name" "$log"
  echo "  $name: $(grep -cE "Test Case .* passed" "$log") UI tests passed; unit tests: $(grep -E 'Test run with' "$log" | tail -n 1 | sed -E 's/^.*(Test run with)/\1/')"
done

echo "step 6: iOS 18"
if dest=$(bash scripts/ios18_destination.sh); then
  FEATHER_IOS_DESTINATION="$dest" bash scripts/test_ios_packages.sh || fail "the shared packages on iOS 18"
  log="$logs/ios-app-ios18.log"
  run_ios_app "$dest" "$log" || fail "the iOS app's tests on iOS 18" "$log"
  echo "  iOS 18: the app's tests passed"
else
  echo "  iOS 18: no runtime installed, skipped"
fi

echo "all tests: OK"

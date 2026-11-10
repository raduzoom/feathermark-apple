#!/usr/bin/env bash
# Every check for the Apple repo, macOS and iOS: the local stand-in for "CI green" (../AGENTS.md "GitHub Actions").
# Runs, in order, and stops at the first failure, naming it:
#   1. scripts/check_paths.sh
#   2. swift test for every package (macOS)
#   3. the shared packages' tests on an iOS simulator (scripts/test_ios_packages.sh)
#   4. the Mac app's full test scheme (app, packages, UI tests)
# Prints "all tests: OK" only when every step passed. Logs go to $TMPDIR/feathermark-all-tests/.
set -uo pipefail
cd "$(dirname "$0")/.."
logs="${TMPDIR:-/tmp}/feathermark-all-tests"
mkdir -p "$logs"

fail() { echo "FAILED: $1${2:+ (log: $2)}" >&2; exit 1; }

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
log="$logs/macos-app.log"
{ xcodegen generate && xcodebuild test -project FeatherNote.xcodeproj -scheme FeatherNote -destination 'platform=macOS'; } > "$log" 2>&1 || fail "the Mac app's xcodebuild test" "$log"
grep -q '\*\* TEST SUCCEEDED \*\*' "$log" || fail "the Mac app's xcodebuild test" "$log"

echo "all tests: OK"

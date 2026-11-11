#!/usr/bin/env bash
# Runs the shared packages' tests on an iOS simulator, one package after another, and stops at the first
# failure, naming it.
#
# Usage: scripts/test_ios_packages.sh [Package...]   (default: every shared package)
# The simulator is the first available iPhone, or FEATHER_IOS_DESTINATION
# (e.g. 'platform=iOS Simulator,name=iPhone 17'). Full logs go to $TMPDIR/feathermark-ios-tests/.
set -uo pipefail
cd "$(dirname "$0")/../Packages"

# Package and the xcodebuild scheme that holds its tests. A package with more than one product gets
# "<Package>-Package"; a package with one product, its own name.
schemes=(
  "FeatherCore:FeatherCore-Package"
  "FeatherCrypto:FeatherCrypto"
  "FeatherSync:FeatherSync"
  "FeatherEditor:FeatherEditor-Package"
  "FeatherAppModel:FeatherAppModel"
)

dest="${FEATHER_IOS_DESTINATION:-}"
if [ -z "$dest" ]; then
  name=$(xcrun simctl list devices available | sed -nE 's/^ +(iPhone[^(]*[^ (]) \(.*/\1/p' | head -n 1)
  if [ -z "$name" ]; then
    echo "no iPhone simulator available; install the iOS platform: xcodebuild -downloadPlatform iOS" >&2
    exit 1
  fi
  dest="platform=iOS Simulator,name=$name"
fi

# Runs one package's tests. xcodebuild can hang after a failing iOS run has printed its summary, so once the
# summary is out it gets 120 s to exit before it's stopped; the summary then decides.
run_tests() {   # package folder, scheme, log
  (cd "$1" && exec xcodebuild test -scheme "$2" -destination "$dest") > "$3" 2>&1 &
  local pid=$! waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if grep -qE '^(✔|✘) Test run with' "$3"; then
      waited=$((waited + 1))
      if [ "$waited" -ge 120 ]; then
        echo "  (xcodebuild didn't exit after the test run; stopped it)" >&2
        kill "$pid" 2>/dev/null
        break
      fi
    fi
    sleep 1
  done
  wait "$pid" 2>/dev/null
  grep -q '\*\* TEST SUCCEEDED \*\*' "$3" && return 0
  grep -qE '^✔ Test run with' "$3" && ! grep -qE '^✘ Test run with|\*\* TEST FAILED \*\*' "$3"
}

wanted=("$@")
logs="${TMPDIR:-/tmp}/feathermark-ios-tests"
mkdir -p "$logs"

for entry in "${schemes[@]}"; do
  package=${entry%%:*}
  scheme=${entry#*:}
  if [ ${#wanted[@]} -gt 0 ] && [[ " ${wanted[*]} " != *" $package "* ]]; then continue; fi
  log="$logs/$package.log"
  echo "iOS tests: $package ($dest)"
  if ! run_tests "$package" "$scheme" "$log"; then
    grep -E 'error:|✘' "$log" | head -n 20 >&2
    echo "FAILED: iOS tests for $package (log: $log)" >&2
    exit 1
  fi
  # a package with several test targets (FeatherEditor: core, Mac view, iPhone view) prints one line each
  grep -E '^✔ Test run with' "$log"
done
echo "iOS packages: OK"

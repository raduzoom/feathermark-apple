#!/usr/bin/env bash
# Fails (exit 1, listing file:line) when a living doc or config still names the
# Apple repo's old folder (mac/) or old GitHub name (feather-note-mac).
# Past phase plans are history and are not checked.
set -uo pipefail
cd "$(dirname "$0")/.."

files=(../AGENTS.md AGENTS.md README.md .github ../server/AGENTS.md ../server/docs ../website/AGENTS.md ../universal/AGENTS.md ../universal/README.md ../universal/plans/feather-note-roadmap.md)
existing=()
for f in "${files[@]}"; do [ -e "$f" ] && existing+=("$f"); done

if grep -rnE '(\.\./mac\b|\bmac/(project\.yml|Packages|FeatherNote|build)|feather-note-mac|working-directory: mac|path: mac)' "${existing[@]}"; then
  echo "stale mac/ paths found (above)" >&2
  exit 1
fi
echo "paths OK"

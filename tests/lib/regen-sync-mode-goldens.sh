#!/usr/bin/env bash
# Regenerates tests/lib/sync-mode-delete-goldens.json: the delete-mode hash of
# every unit, rendered from BASE (default: the merge-base of HEAD and
# upstream/main, i.e. nixflix without this branch's syncMode changes).
#
#   tests/lib/regen-sync-mode-goldens.sh            # merge-base with upstream/main
#   UPSTREAM=origin/main tests/lib/regen-sync-mode-goldens.sh
#   tests/lib/regen-sync-mode-goldens.sh <commit>   # an explicit base
#
# Re-run it after merging upstream changes to the sync units; a unit that
# changes on purpose in delete mode goes into intentionalDeleteChanges in
# tests/unit-tests/sync-mode-coverage.nix instead.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
base=$(git -C "$root" rev-parse "${1:-$(git -C "$root" merge-base HEAD "${UPSTREAM:-upstream/main}")}")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git -C "$root" archive "$base" | tar -x -C "$tmp"
nix eval --impure --json --expr "import $root/tests/lib/sync-mode-goldens.nix { src = $tmp; }" |
  jq --sort-keys --arg base "$base" '{ base: $base, units: . }' > "$root/tests/lib/sync-mode-delete-goldens.json"
echo "wrote tests/lib/sync-mode-delete-goldens.json from $base"

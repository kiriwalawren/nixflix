#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while IFS= read -r -d '' script; do
  echo "==> Running ${script#"$REPO_ROOT/"}"
  bash "$script"
  echo ""
done < <(find "$REPO_ROOT" -name "update.sh" -not -path "*/.git/*" -not -path "*/node_modules/*" -not -path "$REPO_ROOT/update.sh" -print0 | sort -z)

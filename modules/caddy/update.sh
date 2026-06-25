#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET_FILE="$REPO_ROOT/modules/caddy/default.nix"

ARCH=$(uname -m)
case "$ARCH" in
  x86_64) SYSTEM="x86_64-linux" ;;
  aarch64) SYSTEM="aarch64-linux" ;;
  *)
    echo "Unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac

echo "=== Updating Caddy replace-response plugin ==="

# Get latest commit for caddyserver/replace-response
RESPONSE=$(curl -sf "https://api.github.com/repos/caddyserver/replace-response/commits?per_page=1")
NEW_SHA=$(echo "$RESPONSE" | jq -r '.[0].sha')
COMMIT_DATE=$(echo "$RESPONSE" | jq -r '.[0].commit.committer.date')

# Build Go pseudo-version: v0.0.0-YYYYMMDDHHMMSS-<first 12 chars of SHA>
TIMESTAMP=$(date -u -d "$COMMIT_DATE" '+%Y%m%d%H%M%S')
NEW_VERSION="v0.0.0-${TIMESTAMP}-${NEW_SHA:0:12}"

CURRENT_VERSION=$(grep -o 'replace-response@[^"]*' "$TARGET_FILE" | head -1 | cut -d'@' -f2)

if [[ "$NEW_VERSION" == "$CURRENT_VERSION" ]]; then
  echo "  replace-response: already at $CURRENT_VERSION"
  echo "Done."
  exit 0
fi

echo "  replace-response: $CURRENT_VERSION → $NEW_VERSION"

# Update version string first
sed -i "s|replace-response@${CURRENT_VERSION}|replace-response@${NEW_VERSION}|g" "$TARGET_FILE"

# Get current vendorHash
CURRENT_HASH=$(grep -A3 'pkgs.caddy.withPlugins' "$TARGET_FILE" |
  grep 'hash = ' | sed 's/.*hash = "\(.*\)".*/\1/')

# Build with fake hash to obtain the real vendorHash from the error output
TMP_NIX=$(mktemp --suffix=.nix)
trap "rm -f $TMP_NIX" EXIT

cat >"$TMP_NIX" <<EOF
let
  flake = builtins.getFlake "path:${REPO_ROOT}";
  pkgs = flake.inputs.nixpkgs.legacyPackages.${SYSTEM};
in pkgs.caddy.withPlugins {
  plugins = [ "github.com/caddyserver/replace-response@${NEW_VERSION}" ];
  hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
}
EOF

echo "  Computing new vendorHash (this may take a moment)..."
BUILD_OUTPUT=$(nix build --impure --file "$TMP_NIX" --no-link 2>&1 || true)

NEW_HASH=$(echo "$BUILD_OUTPUT" | grep "got:" | grep -o 'sha256-[A-Za-z0-9+/]*=' | tail -1)

if [[ -z "$NEW_HASH" ]]; then
  echo "Error: could not determine new vendorHash" >&2
  echo "nix build output:" >&2
  echo "$BUILD_OUTPUT" >&2
  # Restore original version
  sed -i "s|replace-response@${NEW_VERSION}|replace-response@${CURRENT_VERSION}|g" "$TARGET_FILE"
  exit 1
fi

echo "  New vendorHash: $NEW_HASH"
sed -i "s|${CURRENT_HASH}|${NEW_HASH}|g" "$TARGET_FILE"

echo ""
echo "Done."

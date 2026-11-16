#!/usr/bin/env bash
set -euo pipefail

echo "=== Updating Caddy with replace-response plugin ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEFAULT_NIX="$SCRIPT_DIR/default.nix"
SRC_DIR="$SCRIPT_DIR/src"
FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

for cmd in curl jq go nix nix-prefetch-url; do
  command -v "$cmd" &>/dev/null || {
    echo "error: $cmd not found in PATH (run inside 'nix develop')" >&2
    exit 1
  }
done

CADDY_VERSION=$(curl -fsSL "https://api.github.com/repos/caddyserver/caddy/releases/latest" |
  jq -r '.tag_name | ltrimstr("v")')

RESPONSE=$(curl -fsSL "https://api.github.com/repos/caddyserver/replace-response/commits?per_page=1")
SHA=$(echo "$RESPONSE" | jq -r '.[0].sha')
COMMIT_DATE=$(echo "$RESPONSE" | jq -r '.[0].commit.committer.date')
PLUGIN_VERSION="v0.0.0-$(date -u -d "$COMMIT_DATE" '+%Y%m%d%H%M%S')-${SHA:0:12}"

CURRENT_CADDY=$(grep -oP '(?<=version = ")[^"]+' "$DEFAULT_NIX")
CURRENT_PLUGIN=$(grep -oP '(?<=github.com/caddyserver/replace-response )\S+' "$SRC_DIR/go.mod")

if [[ "$CADDY_VERSION" == "$CURRENT_CADDY" && "$PLUGIN_VERSION" == "$CURRENT_PLUGIN" ]]; then
  echo "  caddy: already at $CURRENT_CADDY"
  echo "  replace-response: already at $CURRENT_PLUGIN"
  echo "Done."
  exit 0
fi

echo "  caddy: $CURRENT_CADDY → $CADDY_VERSION"
echo "  replace-response: $CURRENT_PLUGIN → $PLUGIN_VERSION"

# go.mod's go directive must not exceed caddy's, or older Go toolchains could no longer build it
CADDY_GO=$(curl -fsSL "https://raw.githubusercontent.com/caddyserver/caddy/v${CADDY_VERSION}/go.mod" |
  grep -oP '^go \K\S+')

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/mod"
cp "$SRC_DIR/main.go" "$WORK/mod/"
(
  cd "$WORK/mod"
  go mod init caddy
  go get "github.com/caddyserver/caddy/v2@v${CADDY_VERSION}" "github.com/caddyserver/replace-response@${PLUGIN_VERSION}"
  go mod tidy
  go mod edit -go="${CADDY_GO}" -toolchain=none
)
cp "$WORK/mod/go.mod" "$WORK/mod/go.sum" "$SRC_DIR/"

DIST_HASH=$(nix-prefetch-url --unpack "https://github.com/caddyserver/dist/archive/refs/tags/v${CADDY_VERSION}.tar.gz" 2>/dev/null |
  xargs nix hash convert --hash-algo sha256 --to sri)

CURRENT_DIST_HASH=$(grep -A4 'repo = "dist"' "$DEFAULT_NIX" | grep -oP '(?<=hash = ")[^"]+')
CURRENT_VENDOR_HASH=$(grep -oP '(?<=vendorHash = ")[^"]+' "$DEFAULT_NIX")

sed -i \
  -e "s|version = \"${CURRENT_CADDY}\"|version = \"${CADDY_VERSION}\"|" \
  -e "s|${CURRENT_DIST_HASH}|${DIST_HASH}|" \
  -e "s|${CURRENT_VENDOR_HASH}|${FAKE_HASH}|" \
  "$DEFAULT_NIX"

echo "  Computing new vendorHash (this may take a moment)..."
BUILD_OUTPUT=$(nix build --no-link "path:${REPO_ROOT}#caddy-replace-response" 2>&1 || true)
VENDOR_HASH=$(echo "$BUILD_OUTPUT" | grep "got:" | grep -oP 'sha256-[A-Za-z0-9+/]+=*' | tail -1)

if [[ -z "$VENDOR_HASH" ]]; then
  echo "Error: could not determine new vendorHash" >&2
  echo "$BUILD_OUTPUT" >&2
  git -C "$REPO_ROOT" checkout -- "$DEFAULT_NIX" "$SRC_DIR/go.mod" "$SRC_DIR/go.sum"
  exit 1
fi

echo "  New vendorHash: $VENDOR_HASH"
sed -i "s|${FAKE_HASH}|${VENDOR_HASH}|" "$DEFAULT_NIX"

echo ""
echo "Done."

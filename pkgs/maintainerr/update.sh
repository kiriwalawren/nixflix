#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_NIX="$SCRIPT_DIR/default.nix"
MISSING_HASHES="$SCRIPT_DIR/missing-hashes.json"

for cmd in curl jq nix nix-prefetch-url yarn-berry-fetcher; do
    command -v "$cmd" &>/dev/null || { echo "error: $cmd not found in PATH" >&2; exit 1; }
done

if [[ $# -eq 0 ]]; then
    echo "Fetching latest release from GitHub..." >&2
    VERSION=$(curl -fsSL "https://api.github.com/repos/Maintainerr/Maintainerr/releases/latest" \
        | jq -r '.tag_name | ltrimstr("v")')
    echo "Latest: ${VERSION}" >&2
else
    VERSION="$1"
fi

CURRENT=$(grep -oP '(?<=version = ")[^"]+' "$DEFAULT_NIX" | head -1)
if [[ "$VERSION" == "$CURRENT" ]]; then
    echo "Already at v${VERSION}." >&2
    exit 0
fi
echo "Updating: ${CURRENT} → ${VERSION}" >&2

# Fetch and hash the source tarball (unpacked)
URL="https://github.com/Maintainerr/Maintainerr/archive/refs/tags/v${VERSION}.tar.gz"
echo "Fetching source..." >&2
PREFETCH=$(nix-prefetch-url --unpack --print-path "$URL" 2>/dev/null)
HASH_RAW=$(echo "$PREFETCH" | head -1)
SOURCE_PATH=$(echo "$PREFETCH" | tail -1)
SRC_HASH=$(nix hash to-sri --type sha256 "$HASH_RAW")
echo "src hash: ${SRC_HASH}" >&2

# Regenerate missing-hashes.json from the new yarn.lock
echo "Regenerating missing-hashes.json..." >&2
yarn-berry-fetcher missing-hashes "${SOURCE_PATH}/yarn.lock" > "$MISSING_HASHES"

# Compute offline cache hash
echo "Computing offline cache hash (downloads all deps)..." >&2
CACHE_HASH=$(yarn-berry-fetcher prefetch "${SOURCE_PATH}/yarn.lock" "$MISSING_HASHES")
# Normalise to SRI if the tool emits nix base32
if [[ "$CACHE_HASH" != sha256-* ]]; then
    CACHE_HASH=$(nix hash to-sri --type sha256 "$CACHE_HASH")
fi
echo "offlineCache hash: ${CACHE_HASH}" >&2

# Patch default.nix: version, then src hash (1st occurrence), then cache hash (2nd occurrence)
sed -i "s/version = \"[^\"]*\"/version = \"${VERSION}\"/" "$DEFAULT_NIX"

awk -v src="$SRC_HASH" -v cache="$CACHE_HASH" '
    /hash = "sha256-[^"]*"/ {
        n++
        if (n == 1) { sub(/sha256-[^"]*/, src) }
        else if (n == 2) { sub(/sha256-[^"]*/, cache) }
    }
    { print }
' "$DEFAULT_NIX" > "${DEFAULT_NIX}.tmp" && mv "${DEFAULT_NIX}.tmp" "$DEFAULT_NIX"

echo "Done. Verify with: nix build .#maintainerr" >&2

#!/usr/bin/env bash
set -euo pipefail

echo "=== Updating DroppedNeedle package ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEFAULT_NIX="$SCRIPT_DIR/default.nix"

ARCH=$(uname -m)
case "$ARCH" in
  x86_64) SYSTEM="x86_64-linux" ;;
  aarch64) SYSTEM="aarch64-linux" ;;
  *)
    echo "Unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac

for cmd in curl jq nix nix-prefetch-url perl; do
  command -v "$cmd" &>/dev/null || {
    echo "error: $cmd not found in PATH" >&2
    exit 1
  }
done

if [[ $# -eq 0 ]]; then
  echo "Fetching latest release from GitHub..." >&2
  VERSION=$(curl -fsSL "https://api.github.com/repos/DroppedNeedle/DroppedNeedle/releases/latest" |
    jq -r '.tag_name | ltrimstr("v")')
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
URL="https://github.com/DroppedNeedle/DroppedNeedle/archive/refs/tags/v${VERSION}.tar.gz"
echo "Fetching source..." >&2
PREFETCH=$(nix-prefetch-url --unpack --print-path "$URL" 2>/dev/null)
HASH_RAW=$(echo "$PREFETCH" | head -1)
SRC_HASH=$(nix hash to-sri --type sha256 "$HASH_RAW")
echo "src hash: ${SRC_HASH}" >&2

# Every substitution below is scoped to a specific, uniquely-anchored block
# (via perl slurp-mode regexes, not naive positional sed/awk) so it can never
# touch `esbuildPinned`'s own independent version/src/hash - that pin tracks
# frontend/pnpm-lock.yaml's esbuild resolution, not DroppedNeedle's release
# version, and is deliberately NOT auto-updated here. A naive "replace every
# version = "..." / hash = "..." line" approach clobbers esbuildPinned's
# fields too, since it uses the exact same field names.
export NEW_VERSION="$VERSION"
export NEW_SRC_HASH="$SRC_HASH"
export FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

# 1. App version: the `pname = "droppedneedle";` / `version = "...";` pair.
perl -0777 -pi -e '
  s/(pname = "droppedneedle";\n  version = ")[^"]+(")/$1$ENV{NEW_VERSION}$2/;
' "$DEFAULT_NIX"

# 2. App source hash: anchored to the DroppedNeedle fetchFromGitHub block.
perl -0777 -pi -e '
  s/(owner = "DroppedNeedle";\n    repo = "DroppedNeedle";\n    tag = "v\$\{version\}";\n    hash = ")[^"]+(")/$1$ENV{NEW_SRC_HASH}$2/;
' "$DEFAULT_NIX"

# 3. Blank the pnpmDeps hash (anchored to the pnpmDeps block specifically) so
#    the next build fails with a hash mismatch we can scrape the real value
#    from.
perl -0777 -pi -e '
  s/(pnpmDeps = fetchPnpmDeps \{.*?hash = ")[^"]+(")/$1$ENV{FAKE_HASH}$2/s;
' "$DEFAULT_NIX"

# Resolve the pnpmDeps hash the standard fetchPnpmDeps way: build with the
# blank/fake hash and read the real one from the reproducible hash-mismatch
# error. nixpkgs has no dedicated single-command pnpm prefetcher (unlike
# fetchNpmDeps' `prefetch-npm-deps` or fetchYarnDeps' fetch-yarn-deps) - this
# build-and-read-the-mismatch cycle is the workflow pnpmConfigHook itself
# documents as the only way (see its own error message in
# pkgs/build-support/node/fetch-pnpm-deps/pnpm-config-hook.sh upstream).
#
# Building just `droppedneedle.pnpmDeps` (exposed via passthru in default.nix)
# rather than the whole package keeps this fast and, importantly, avoids ever
# reading the wrong "got:" line - the full package build also rebuilds
# esbuildPinned from source, and if ITS hash ever needed updating too, both
# mismatches would land in the same output with no reliable way to tell them
# apart. Built against an explicit flake path (not `.#droppedneedle`) so this
# script works regardless of the caller's current directory.
#
# The "specified:"/"got:" wording comes from Nix's own fixed-output-derivation
# hash verification - the same mechanism and message used for every fetcher
# (fetchurl, fetchFromGitHub, fetchNpmDeps, ...), not something specific to
# pnpm or this package, so it's about as stable as any Nix internal can be.
# If the grep below ever stops matching, run
# `nix build .#droppedneedle.pnpmDeps` by hand and copy the "got:" hash.
echo "Computing pnpm offline store hash (this fetches all frontend deps)..." >&2
MISMATCH=$(nix build --impure --no-link --show-trace \
  --expr "(builtins.getFlake \"path:${REPO_ROOT}\").packages.${SYSTEM}.droppedneedle.pnpmDeps" 2>&1 || true)
CACHE_HASH=$(echo "$MISMATCH" | grep "got:" | grep -o 'sha256-[A-Za-z0-9+/]*=' | tail -1)
if [[ -z "$CACHE_HASH" ]]; then
  echo "error: could not extract pnpmDeps hash from build output" >&2
  echo "$MISMATCH" >&2
  exit 1
fi
echo "pnpmDeps hash: ${CACHE_HASH}" >&2

export NEW_PNPM_HASH="$CACHE_HASH"
perl -0777 -pi -e '
  s/(pnpmDeps = fetchPnpmDeps \{.*?hash = ")[^"]+(")/$1$ENV{NEW_PNPM_HASH}$2/s;
' "$DEFAULT_NIX"

echo "" >&2
echo "NOTE: esbuildPinned's version/src/hash were left untouched. If this" >&2
echo "      release's frontend/pnpm-lock.yaml pins a different esbuild" >&2
echo "      version, update esbuildPinned by hand in $DEFAULT_NIX." >&2
echo "" >&2
echo "Done. Verify with: nix build .#droppedneedle" >&2

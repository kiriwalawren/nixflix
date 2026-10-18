#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/.source-cache"
SOURCES_FILE="$SCRIPT_DIR/sources.txt"
CONCURRENCY="${FETCH_MANIFEST_CONCURRENCY:-8}"

JELLYFIN_VERSION="${JELLYFIN_VERSION:-${1:-}}"
if [ -z "$JELLYFIN_VERSION" ]; then
  echo "Usage: JELLYFIN_VERSION=<version> $0, or $0 <version>" >&2
  exit 1
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

mkdir -p "$CACHE_DIR"

fetch_with_retry() {
  curl -sS --fail -L \
    --retry 4 --retry-connrefused --retry-all-errors --retry-max-time 45 \
    --connect-timeout 5 --max-time 20 \
    -A "jellyfin/$JELLYFIN_VERSION (https://github.com/kiriwalawren/nixflix)" \
    -o "$2" "$1"
}

strip_bom() {
  if [ "$(head -c3 "$1" | od -An -tx1 | tr -d ' \n')" = "efbbbf" ]; then
    tail -c +4 "$1" >"$1.nobom" && mv "$1.nobom" "$1"
  fi
}

fetch_one_source() {
  local url="$1" key cache_file out_file tmp
  key="$(printf '%s' "$url" | sha256sum | cut -d' ' -f1)"
  cache_file="$CACHE_DIR/$key.json"
  out_file="$WORKDIR/$key.json"
  tmp="$(mktemp)"

  if fetch_with_retry "$url" "$tmp" && { strip_bom "$tmp"; jq -e 'type == "array"' "$tmp" >/dev/null 2>&1; }; then
    cp "$tmp" "$cache_file.tmp" && mv "$cache_file.tmp" "$cache_file"
    printf '%s\n' "$url" >"$CACHE_DIR/$key.url"
    mv "$tmp" "$out_file"
    return 0
  fi
  rm -f "$tmp"

  if [ -f "$cache_file" ]; then
    echo "WARN: fetch failed for $url, using stale cached copy" >&2
    cp "$cache_file" "$out_file"
    return 0
  fi

  echo "WARN: fetch failed for $url and no cached copy exists; skipping" >&2
  return 1
}

export -f fetch_with_retry strip_bom fetch_one_source
export CACHE_DIR WORKDIR JELLYFIN_VERSION

if [ ! -f "$SOURCES_FILE" ]; then
  echo "ERROR: $SOURCES_FILE does not exist" >&2
  exit 1
fi

mapfile -t MANIFEST_URLS < <(
  jq -R -r '
    gsub("\r$"; "")
    | select(test("^[[:space:]]*(#.*)?$") | not)
    | (split("|")[0] | gsub("^[[:space:]]+|[[:space:]]+$"; ""))
  ' "$SOURCES_FILE"
)

echo "Discovered ${#MANIFEST_URLS[@]} candidate plugin source manifests" >&2
if [ "${#MANIFEST_URLS[@]}" -lt 100 ]; then
  echo "ERROR: only ${#MANIFEST_URLS[@]} sources parsed from sources.txt (expected ~260)" >&2
  exit 1
fi

printf '%s\n' "${MANIFEST_URLS[@]}" |
  xargs -P "$CONCURRENCY" -I{} bash -c 'fetch_one_source "$1"' _ {} || true

shopt -s nullglob
files=("$WORKDIR"/*.json)
shopt -u nullglob

if [ "${#files[@]}" -eq 0 ]; then
  echo "ERROR: no source manifests were fetched successfully (not even from cache)" >&2
  exit 1
fi

RESULT="$(jq -s --arg jfv "$JELLYFIN_VERSION" '
  def pad4:
    (tostring | split(".") | map((tonumber?) // 0)) as $n
    | if ($n | length) >= 4
      then $n[0:4]
      else $n + ([range(4 - ($n | length))] | map(0))
      end;

  ($jfv | pad4) as $jf
  | [12, 0, 0, 0] as $v12
  | (map(select(type == "array")) | add // []) as $plugins
  | $plugins
  | map(
      .versions = (
        [ .versions[]?
          | select(
              (.targetAbi | pad4) as $abi
              | ($jf >= $abi) and (($jf < $v12) or ($abi >= $v12))
            )
        ]
      )
    )
  | map(select((.versions | length) > 0))
' "${files[@]}")"

COUNT="$(echo "$RESULT" | jq 'length')"
echo "Aggregated $COUNT ABI-compatible plugins from ${#files[@]}/${#MANIFEST_URLS[@]} sources" >&2

if [ "$COUNT" -lt 10 ]; then
  echo "ERROR: only $COUNT plugins after aggregation/filtering (expected at least 10)" >&2
  exit 1
fi

echo "$RESULT"

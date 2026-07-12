#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# === Part 1: Update manifest hashes ===

echo "=== Updating Jellyfin plugin manifests ==="

update_manifest() {
  local name="$1"
  local new_sha="$2"
  local new_url="$3"
  local new_hash="$4"
  local sha_pattern="$5"

  local old_sha
  old_sha=$(grep -roh "$sha_pattern" "$REPO_ROOT" --include="*.nix" | head -1 | grep -o '[0-9a-f]\{40\}')

  if [[ "$new_sha" == "$old_sha" ]]; then
    echo "  $name: already at ${new_sha:0:8}"
    return
  fi

  local old_hash_file old_hash
  old_hash_file=$(grep -rl "$old_sha" "$REPO_ROOT" --include="*.nix" | head -1)
  old_hash=$(grep -A3 "$old_sha" "$old_hash_file" | grep 'hash = ' | head -1 | sed 's/.*hash = "\(.*\)".*/\1/')

  echo "  $name: ${old_sha:0:8} → ${new_sha:0:8}"
  find "$REPO_ROOT" -name "*.nix" -not -path "*/.git/*" \
    -exec sed -i "s|${old_sha}|${new_sha}|g; s|${old_hash}|${new_hash}|g" {} \;
}

echo "Fetching Jellyfin Stable Plugin Repo..."
UPR_SHA=$(curl -sf \
  "https://api.github.com/repos/kiriwalawren/nixflix/commits/main?per_page=1" |
  jq -r '.sha')
UPR_URL="https://raw.githubusercontent.com/kiriwalawren/nixflix/${UPR_SHA}/modules/jellyfin/system/jellyfin-stable-plugin-manifest.json"
UPR_HASH=$(nix store prefetch-file --json "$UPR_URL" 2>/dev/null | jq -r '.hash')

update_manifest "Stable Plugin Repo" \
  "$UPR_SHA" "$UPR_URL" "$UPR_HASH" \
  'kiriwalawren/nixflix/[0-9a-f]\{40\}/modules/jellyfin/system/jellyfin-stable-plugin-manifest'

UPR_MANIFEST=$(curl -sf "$UPR_URL")

echo "Fetching SubBuzz manifest..."
SUBBUZZ_SHA=$(curl -sf \
  "https://api.github.com/repos/josdion/subbuzz/commits?path=repo/jellyfin_10.11.json&per_page=1" |
  jq -r '.[0].sha')
SUBBUZZ_URL="https://raw.githubusercontent.com/josdion/subbuzz/${SUBBUZZ_SHA}/repo/jellyfin_10.11.json"
SUBBUZZ_MANIFEST_HASH=$(nix store prefetch-file --json "$SUBBUZZ_URL" 2>/dev/null | jq -r '.hash')

update_manifest "SubBuzz manifest" \
  "$SUBBUZZ_SHA" "$SUBBUZZ_URL" "$SUBBUZZ_MANIFEST_HASH" \
  'josdion/subbuzz/[0-9a-f]\{40\}/repo'

SUBBUZZ_MANIFEST=$(curl -sf "$SUBBUZZ_URL")

# === Part 2: Update plugin version + download hashes ===

echo ""
echo "=== Updating Jellyfin plugin versions ==="

discover_fromrepo() {
  find "$REPO_ROOT" -name "*.nix" -not -path "*/.git/*" -print0 |
    xargs -0 gawk '
    FNR == 1 { delete history; in_fromrepo = 0; block_depth = 0 }
    { history[FNR] = $0 }
    /fromRepo[[:space:]]*\{/ && !/^[[:space:]]*#/ && !in_fromrepo {
      in_fromrepo = 1
      block_depth = 0
      plugin_name = version = hash_val = ""
      for (i = FNR - 1; i >= (FNR - 10 > 1 ? FNR - 10 : 1); i--) {
        h = history[i]
        if (match(h, /plugins\."([^"]+)"/, a)) { plugin_name = a[1]; break }
        if (match(h, /plugins\.([A-Za-z][A-Za-z0-9_-]*)[ \t]*[={]/, a)) { plugin_name = a[1]; break }
        if (match(h, /"([A-Z][^"]*)"[ \t]*=[ \t]*\{/, a)) { plugin_name = a[1]; break }
      }
    }
    in_fromrepo {
      for (j = 1; j <= length($0); j++) {
        c = substr($0, j, 1)
        if (c == "{") block_depth++
        else if (c == "}") block_depth--
      }
      if (match($0, /version[ \t]*=[ \t]*"([^"]+)"/, a)) version = a[1]
      if (match($0, /hash[ \t]*=[ \t]*"([^"]+)"/, a)) hash_val = a[1]
      if (block_depth <= 0) {
        if (plugin_name != "" && version != "" && hash_val != "")
          print FILENAME "\t" plugin_name "\t" version "\t" hash_val
        in_fromrepo = 0
      }
    }
    '
}

lookup_in_manifest() {
  local plugin_name="$1"
  local manifest_json="$2"
  echo "$manifest_json" | jq -r \
    --arg name "$plugin_name" \
    '[.[] | select(.name == $name) | .versions[]]
     | if length == 0 then empty
       else sort_by(.version | split(".") | map(tonumber)) | last
       | (.version + "\t" + .sourceUrl)
       end' 2>/dev/null
}

MANIFESTS=("$UPR_MANIFEST" "$SUBBUZZ_MANIFEST")

while IFS=$'\t' read -r nix_file plugin_name current_version current_hash; do
  latest_info=""
  for manifest in "${MANIFESTS[@]}"; do
    latest_info=$(lookup_in_manifest "$plugin_name" "$manifest")
    [[ -n "$latest_info" ]] && break
  done

  if [[ -z "$latest_info" ]]; then
    echo "  $plugin_name: not found in any manifest, skipping"
    continue
  fi

  latest_version=$(cut -f1 <<<"$latest_info")
  source_url=$(cut -f2 <<<"$latest_info")

  if [[ "$latest_version" == "$current_version" ]]; then
    echo "  $plugin_name: already at $current_version"
    continue
  fi

  new_hash=$(nix store prefetch-file --json --unpack "$source_url" 2>/dev/null | jq -r '.hash')

  echo "  $plugin_name: $current_version → $latest_version"
  sed -i "s|version = \"${current_version}\"|version = \"${latest_version}\"|g" "$nix_file"
  sed -i "s|${current_hash}|${new_hash}|g" "$nix_file"

done < <(discover_fromrepo)

echo ""
echo "Done."

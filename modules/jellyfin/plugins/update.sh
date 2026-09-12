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

echo "Fetching Jellyfin Universal Plugin Repo Manifest..."
UPR_SHA=$(curl -sf \
  "https://api.github.com/repos/kiriwalawren/nixflix/commits/main?per_page=1" |
  jq -r '.sha')
UPR_URL="https://raw.githubusercontent.com/kiriwalawren/nixflix/${UPR_SHA}/modules/jellyfin/system/jellyfin-universal-plugin-manifest.json"
UPR_HASH=$(nix store prefetch-file --json "$UPR_URL" 2>/dev/null | jq -r '.hash')

update_manifest "Universal Plugin Repo" \
  "$UPR_SHA" "$UPR_URL" "$UPR_HASH" \
  'kiriwalawren/nixflix/[0-9a-f]\{40\}/modules/jellyfin/system/jellyfin-universal-plugin-manifest'

UPR_MANIFEST=$(curl -sf "$UPR_URL")

# === Part 2: Update plugin version + download hashes ===

echo ""
echo "=== Updating Jellyfin plugin versions ==="

update_plugins() {
  current_plugins_json="$(cat modules/jellyfin/plugins/plugins.json)"
  plugins_json="{"
  # We want to split on newline when iterating over JSON for plugins and versions
  IFS=$'\n'
  for plugin in $(echo "$UPR_MANIFEST" | jq -c '.[]');
  do
    # Exclude plugins starting with "!" (i.e. the universal plugins repo plugin)
    if [[ $(echo "$plugin" | jq -r '.name') =~ ^! ]]; then
      continue
    fi
    versions_json="["
    for version in $(echo "$plugin" | jq -c '.versions[]');
    do
      local local_plugin="$(echo "$current_plugins_json" | jq ".$(echo "$plugin" | jq '.name')")"
      if [ "$local_plugin" != "null" ]; then
        for local_version in $(echo "$local_plugin" | jq -c '.versions[]'); do
          if [ "$(echo "$version" | jq '.version')" = "$(echo "$local_version" | jq '.version')" ]; then
            versions_json="$versions_json$local_version,"
            continue 2
          fi
        done
      fi
      local hash="$(nix flake prefetch --json "$(echo "$version" | jq -r '.sourceUrl')" | jq '.hash')"
      if [ -n "$hash" ]; then
        # Only add version if hash is set, otherwise, skip it (usually due to 404 on sourceUrl)
        echo "New version of $(echo "$plugin" | jq '.name') found: $(echo "$version" | jq '.version')"
        versions_json="$versions_json
          {
            \"version\": $(echo "$version" | jq '.version'),
            \"changelog\": $(echo "$version" | jq '.changelog'),
            \"targetAbi\": $(echo "$version" | jq '.targetAbi'),
            \"url\": $(echo "$version" | jq '.sourceUrl'),
            \"hash\": $hash,
            \"timestamp\": $(echo "$version" | jq '.timestamp')
          },"
      fi
    done;
    versions_json="$(echo $versions_json | sed "s/,*$/]/")" 

    plugins_json="$plugins_json
      $(echo $plugin | jq '.name'): {
        \"guid\": $(echo "$plugin" | jq '.guid'),
        \"overview\": $(echo "$plugin" | jq '.overview'),
        \"description\": $(echo "$plugin" | jq '.description'),
        \"owner\": $(echo "$plugin" | jq '.owner'),
        \"category\": $(echo "$plugin" | jq '.category'),
        \"imageUrl\": $(echo "$plugin" | jq '.imageUrl'),
        \"versions\": $versions_json
      },"
  done;
  echo $plugins_json | sed "s/,$/}/" | jq > modules/jellyfin/plugins/plugins.json
}

update_plugins

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

while IFS=$'\t' read -r nix_file plugin_name current_version current_hash; do
  latest_info=$(lookup_in_manifest "$plugin_name" "$UPR_MANIFEST")

  if [[ -z "$latest_info" ]]; then
    echo "  $plugin_name: not found in manifest, skipping"
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

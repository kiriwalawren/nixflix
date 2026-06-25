#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
OPTIONS_NIX="$REPO_ROOT/modules/jellyfin/system/options.nix"
SUBBUZZ_NIX="$REPO_ROOT/modules/jellyfin/plugins/subbuzz.nix"
OPEN_SUBTITLES_NIX="$REPO_ROOT/modules/jellyfin/plugins/openSubtitles.nix"
SUBTITLE_EXTRACT_NIX="$REPO_ROOT/modules/jellyfin/plugins/subtitleExtract.nix"
DEFAULT_NIX="$REPO_ROOT/modules/jellyfin/plugins/default.nix"

# === Part 1: Update manifest hashes ===

echo "=== Updating Jellyfin plugin manifests ==="

# --- Universal Plugin Repo ---
echo "Fetching Jellyfin Universal Plugin Repo..."
NEW_UPR_SHA=$(curl -sf \
  "https://api.github.com/repos/0belous/Jellyfin-Universal-Plugin-Repo/commits/main?per_page=1" |
  jq -r '.sha')
NEW_UPR_URL="https://raw.githubusercontent.com/0belous/Jellyfin-Universal-Plugin-Repo/${NEW_UPR_SHA}/manifest.json"
NEW_UPR_HASH=$(nix store prefetch-file --json "$NEW_UPR_URL" 2>/dev/null | jq -r '.hash')

OLD_UPR_SHA=$(grep -o 'Jellyfin-Universal-Plugin-Repo/[0-9a-f]\{40\}/manifest' "$OPTIONS_NIX" |
  grep -o '[0-9a-f]\{40\}')
OLD_UPR_HASH=$(grep -A3 '"Jellyfin Universal Plugin Repo"' "$OPTIONS_NIX" |
  grep 'hash = ' | sed 's/.*hash = "\(.*\)".*/\1/')

if [[ "$NEW_UPR_SHA" == "$OLD_UPR_SHA" ]]; then
  echo "  Universal Plugin Repo: already at ${NEW_UPR_SHA:0:8}"
else
  echo "  Universal Plugin Repo: ${OLD_UPR_SHA:0:8} → ${NEW_UPR_SHA:0:8}"
  sed -i "s|${OLD_UPR_SHA}|${NEW_UPR_SHA}|g" "$OPTIONS_NIX"
  sed -i "s|${OLD_UPR_HASH}|${NEW_UPR_HASH}|g" "$OPTIONS_NIX"
fi

UPR_MANIFEST=$(curl -sf "$NEW_UPR_URL")

# --- SubBuzz manifest ---
echo "Fetching SubBuzz manifest..."
NEW_SUBBUZZ_SHA=$(curl -sf \
  "https://api.github.com/repos/josdion/subbuzz/commits?path=repo/jellyfin_10.11.json&per_page=1" |
  jq -r '.[0].sha')
NEW_SUBBUZZ_URL="https://raw.githubusercontent.com/josdion/subbuzz/${NEW_SUBBUZZ_SHA}/repo/jellyfin_10.11.json"
NEW_SUBBUZZ_MANIFEST_HASH=$(nix store prefetch-file --json "$NEW_SUBBUZZ_URL" 2>/dev/null | jq -r '.hash')

OLD_SUBBUZZ_SHA=$(grep -o 'josdion/subbuzz/[0-9a-f]\{40\}/repo' "$SUBBUZZ_NIX" |
  grep -o '[0-9a-f]\{40\}')
OLD_SUBBUZZ_MANIFEST_HASH=$(grep -A2 "josdion/subbuzz/${OLD_SUBBUZZ_SHA}" "$SUBBUZZ_NIX" |
  grep 'hash = ' | sed 's/.*hash = "\(.*\)".*/\1/')

if [[ "$NEW_SUBBUZZ_SHA" == "$OLD_SUBBUZZ_SHA" ]]; then
  echo "  SubBuzz manifest: already at ${NEW_SUBBUZZ_SHA:0:8}"
else
  echo "  SubBuzz manifest: ${OLD_SUBBUZZ_SHA:0:8} → ${NEW_SUBBUZZ_SHA:0:8}"
  sed -i "s|${OLD_SUBBUZZ_SHA}|${NEW_SUBBUZZ_SHA}|g" "$SUBBUZZ_NIX"
  sed -i "s|${OLD_SUBBUZZ_MANIFEST_HASH}|${NEW_SUBBUZZ_MANIFEST_HASH}|g" "$SUBBUZZ_NIX"
fi

SUBBUZZ_MANIFEST=$(curl -sf "$NEW_SUBBUZZ_URL")

# === Part 2: Update plugin version + download hashes ===

echo ""
echo "=== Updating Jellyfin plugin versions ==="

update_plugin() {
  local plugin_name="$1"
  local manifest_json="$2"
  local nix_file="$3"

  local latest_version
  latest_version=$(echo "$manifest_json" | jq -r \
    --arg name "$plugin_name" \
    '[.[] | select(.name == $name) | .versions[]]
         | sort_by(.version | split(".") | map(tonumber))
         | last | .version')

  if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
    echo "  $plugin_name: not found in manifest, skipping"
    return
  fi

  local source_url
  source_url=$(echo "$manifest_json" | jq -r \
    --arg name "$plugin_name" --arg ver "$latest_version" \
    '.[] | select(.name == $name) | .versions[] | select(.version == $ver) | .sourceUrl')

  local current_version
  current_version=$(grep -o 'version = "[0-9][^"]*"' "$nix_file" | head -1 |
    sed 's/version = "\(.*\)"/\1/')

  if [[ "$latest_version" == "$current_version" ]]; then
    echo "  $plugin_name: already at $current_version"
    return
  fi

  echo "  $plugin_name: $current_version → $latest_version"

  local new_hash
  new_hash=$(nix store prefetch-file --json --unpack "$source_url" 2>/dev/null | jq -r '.hash')

  local current_hash
  current_hash=$(grep -o 'hash = "sha256-[A-Za-z0-9+/]*="' "$nix_file" | head -1 |
    sed 's/hash = "\(.*\)"/\1/')

  sed -i "s|version = \"${current_version}\"|version = \"${latest_version}\"|g" "$nix_file"
  sed -i "s|${current_hash}|${new_hash}|g" "$nix_file"
}

update_plugin "AniDB" "$UPR_MANIFEST" "$DEFAULT_NIX"
update_plugin "Open Subtitles" "$UPR_MANIFEST" "$OPEN_SUBTITLES_NIX"
update_plugin "Subtitle Extract" "$UPR_MANIFEST" "$SUBTITLE_EXTRACT_NIX"
update_plugin "subbuzz" "$SUBBUZZ_MANIFEST" "$SUBBUZZ_NIX"

echo ""
echo "Done."

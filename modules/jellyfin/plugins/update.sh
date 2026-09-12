#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# === Part 1: Fetch UPR manifest ===

echo "Fetching Jellyfin Universal Plugin Repo Manifest..."
NIXPKGS_REV=$(jq -r '.nodes.nixpkgs.locked.rev' flake.lock)
JELLYFIN_VERSION=$(nix eval --raw "github:NixOS/nixpkgs/${NIXPKGS_REV}#jellyfin.version")
UPR_URL="https://obelo.us/upr"
UPR_MANIFEST=$(curl -sfA "jellyfin/$JELLYFIN_VERSION (https://github.com/kiriwalawren/nixflix)" "$UPR_URL")

# === Part 2: Update plugin versions JSON ===

echo ""
echo "=== Updating Jellyfin plugin versions JSON ==="

update_plugins() {
  # These are the keys which we use to identify a version, since the `version` alone isn't
  # gaurenteed to be unique (e.g. two identical versions with different `targetAbi`s)
  VERSION_COMPARE_KEYS_FILTER='{checksum, sourceUrl, targetAbi, timestamp, version} | with_entries(select(.value != null))'
  current_plugins_json="$(cat modules/jellyfin/plugins/plugins.json)"
  plugins_json="{}"
  # We want to split on newline when iterating over JSON for plugins and versions
  IFS=$'\n'

  for plugin in $(echo "$UPR_MANIFEST" | jq -c '.[]');
  do
    # Exclude plugins starting with "!" (i.e. the universal plugins repo plugin)
    if [[ $(echo "$plugin" | jq -r '.name') =~ ^! ]]; then
      continue
    fi
    local guid="$(echo "$plugin" | jq -r '.guid')"
    # Also, a plugin called "Xtream Library" has changed guids for some reason,
    # and UPR still provides the old one, so let's skip it when we find it:
    if [ $guid = a1b2c3d4-e5f6-7890-abcd-ef1234567890 ]; then
      continue
    fi
    # There are two plugins with the exact same name, "Missing Episodes", so let's skip the one which:
    # - Seems to be entirely vibecoded (12 commits with copilot, then nothing for 6 months)
    # - Is likely much less useful (just provides API endpoints for missing episodes)
    if [ $guid = 3e7a8e72-8a85-4b2d-9f3c-1a2b3c4d5e6f ]; then
      continue
    fi
    # Similar to above, but this duplicate plugin just seems to have the same functionality as the
    # existing ListenBrainz plugin
    if [ $guid = b8e7f6a5-4d3c-2b1a-0f9e-8d7c6b5a4f3e ]; then
      continue
    fi
    # UPR adds " [✓*]" to some plugin names for some reason, so we have to remove them
    name="$(echo "$plugin" | jq '.name' | sed 's/ \[✓*\]"$/"/')"
    # Remove the UPR metadata added to the description, it isn't really helpful and just generates
    # noisy diffs
    description="$(echo "$plugin" | jq '.description' | sed 's~  \\n  \\nUniversal Repo:  \\nGenerated: [0-9]\{2\}:[0-9]\{2\} UTC  \\nSource: https://.*  \\n.*"$~"~')"

    versions_json="[]"
    # Try to load existing plugin object, so that if multiple versions of the 
    local existing_plugin="$(echo "$plugins_json" | jq -c ."$name")"
    if [ "$existing_plugin" != null ]; then
      if [ "$(echo "$existing_plugin" | jq .guid)" = "$(echo "$plugin" | jq .guid)" ]; then
        # It exists, so let's add new versions to it
        versions_json="$(echo "$existing_plugin" | jq .versions)"
      else
        # Plugin with identical name but different GUID found. Let's exit here, so that when the
        # pipeline fails, a maintainer can choose to skip one of them from the plugins json
        # manually, like shown above.
        echo "Duplicate plugin $name found, please block one of them from being included"
        exit 1
      fi
    fi

    for version in $(echo "$plugin" | jq -c '.versions[]');
    do
      for existing_version in $(echo "$versions_json" | jq -c '.[]'); do
        if [ "$(echo "$version" | jq -c $VERSION_COMPARE_KEYS_FILTER)" = "$(echo "$existing_version" | jq -c $VERSION_COMPARE_KEYS_FILTER)" ]; then
          # Existing version exists which appears to be identical, so let's skip it
          continue 2
        fi
      done
      local local_plugin="$(echo "$current_plugins_json" | jq ".$name")"
      # Checking if we already have this version hash locally, saving time in getting the nix hash
      if [ "$local_plugin" != "null" ]; then
        for local_version in $(echo "$local_plugin" | jq -c '.versions[]'); do
          if [ "$(echo "$version" | jq -c $VERSION_COMPARE_KEYS_FILTER)" = "$(echo "$local_version" | jq -c $VERSION_COMPARE_KEYS_FILTER)" ]; then
            versions_json="$(echo "$versions_json[$local_version]" | jq -sc "add")"
            continue 2
          fi
        done
      fi
      local hash="$(nix flake prefetch --json "$(echo "$version" | jq -r '.sourceUrl')" | jq '.hash')"
      if [ -n "$hash" ]; then
        # Only add version if hash is set, otherwise, skip it (usually due to 404 on sourceUrl)
        echo "New or updated version of $name found: $(echo "$version" | jq '.version')"
        versions_json="$(echo "$versions_json" | jq ". +=[$(echo "$version" | jq -c "{changelog, checksum, sourceUrl, targetAbi, timestamp, version} + {hash: $hash} | with_entries(select(.value != null))")]")"
      fi
    done;
    # Have to do it this way to avoid "Argument list too long" error due to adding versions_json
    plugins_json="$(echo "$plugins_json{$name: $(echo "$plugin{\"description\": $description}{\"versions\": $versions_json}" | jq -sc "add | {guid, overview, description, owner, category, imageUrl, versions} | with_entries(select(.value != null))")}" | jq -sc "add")"
  done;
  # Sort the plugins for consistency
  echo "$plugins_json" | jq -S > modules/jellyfin/plugins/plugins.json
}

update_plugins

# === Part 3: Update plugin versions + download hashes for tests & examples ===

echo ""
echo "=== Updating example/test Jellyfin plugin versions ==="

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
    '[.[] | select((.name | sub(" \\[✓+\\]$"; "")) == $name) | .versions[]]
     | if length == 0 then empty
       else sort_by(.version | split(".") | map(tonumber)) | last
       | (.version + "\t" + .sourceUrl)
       end' 2>/dev/null
}

lookup_source_url_for_version() {
  local plugin_name="$1"
  local version="$2"
  local manifest_json="$3"
  echo "$manifest_json" | jq -r \
    --arg name "$plugin_name" --arg version "$version" \
    '[.[] | select((.name | sub(" \\[✓+\\]$"; "")) == $name) | .versions[] | select(.version == $version) | .sourceUrl]
     | first // empty' 2>/dev/null
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

  # Fixture manifests may embed the old sourceUrl literally; keep it in sync.
  old_source_url=$(lookup_source_url_for_version "$plugin_name" "$current_version" "$UPR_MANIFEST")
  if [[ -n "$old_source_url" && "$old_source_url" != "$source_url" ]]; then
    sed -i "s|${old_source_url}|${source_url}|g" "$nix_file"
  fi

  # Propagate the plugin directory name into any tests asserting on it.
  find "$REPO_ROOT" -name "*.nix" -not -path "*/.git/*" \
    -exec sed -i "s|${plugin_name}_${current_version}|${plugin_name}_${latest_version}|g" {} \;

done < <(discover_fromrepo)

echo ""
echo "Done."

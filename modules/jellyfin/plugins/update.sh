#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# === Part 1: Fetch plugin source manifests ===

echo "Fetching Jellyfin plugin source manifests..."
JELLYFIN_VERSION=$(nix eval --raw --inputs-from "$REPO_ROOT" nixpkgs#jellyfin.version)

SOURCE_MANIFEST=$("$REPO_ROOT/modules/jellyfin/plugins/fetch-manifest.sh" "$JELLYFIN_VERSION")

# === Part 2: Update plugin versions JSON ===

echo ""
echo "=== Updating Jellyfin plugin versions JSON ==="

prefetch_one() {
  local url label hash
  IFS=$'\t' read -r url label <<<"$1"
  hash="$(nix flake prefetch --json "$url" 2>/dev/null | jq -r '.hash // empty' || true)"
  if [ -n "$hash" ]; then
    printf '%s\t%s\n' "$url" "$hash" >"$2/$(printf '%s' "$url" | sha256sum | cut -d' ' -f1)"
    printf 'ok\t%s\n' "$label"
  else
    printf 'failed\t%s (%s)\n' "$label" "$url"
  fi
}

update_plugins() {
  local plugins_file="$REPO_ROOT/modules/jellyfin/plugins/plugins.json"
  local concurrency="${PLUGIN_PREFETCH_CONCURRENCY:-$(nproc)}"
  local workdir
  workdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$workdir'" EXIT

  local blocked_guids=(
    # A plugin called "Xtream Library" has changed guids for some reason, and the old one is still
    # published, so let's skip it
    "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
    # There are two plugins with the exact same name, "Missing Episodes", so let's skip the one which:
    # - Seems to be entirely vibecoded (12 commits with copilot, then nothing for 6 months)
    # - Is likely much less useful (just provides API endpoints for missing episodes)
    "3e7a8e72-8a85-4b2d-9f3c-1a2b3c4d5e6f"
    # Similar to above, but this duplicate plugin just seems to have the same functionality as the
    # existing ListenBrainz plugin
    "b8e7f6a5-4d3c-2b1a-0f9e-8d7c6b5a4f3e"
  )

  printf '%s' "$SOURCE_MANIFEST" | jq -c --args '$ARGS.positional as $blocked | map(select(.guid as $g | $blocked | index($g) | not))' "${blocked_guids[@]}" >"$workdir/manifest.json"

  # Plugin with identical name but different GUID found. Let's exit here, so that when the
  # pipeline fails, a maintainer can choose to skip one of them from the plugins json
  # manually, like shown above.
  local duplicates
  duplicates="$(jq -r 'group_by(.name)[] | select((map(.guid) | unique | length) > 1) | .[0].name | tojson' "$workdir/manifest.json")"
  if [ -n "$duplicates" ]; then
    while IFS= read -r name; do
      echo "Duplicate plugin $name found, please block one of them from being included"
    done <<<"$duplicates"
    exit 1
  fi

  # Merge plugins sharing a name, dedupe their versions, and reuse already known hashes.
  # These are the keys which we use to identify a version, since the `version` alone isn't
  # gaurenteed to be unique (e.g. two identical versions with different `targetAbi`s)
  jq -c --slurpfile current "$plugins_file" '
    def compareKey: {checksum, sourceUrl, targetAbi, timestamp, version} | with_entries(select(.value != null)) | tojson;
    def pad4: (tostring | split(".") | map((tonumber?) // 0)) as $n | ($n + [0, 0, 0, 0])[0:4];

    ($current[0] | map_values(.versions | map({key: compareKey, value: .}) | from_entries)) as $known
    | reduce .[] as $plugin ({};
        .[$plugin.name] as $existing
        | .[$plugin.name] = (
            ($plugin | {guid, overview, description, owner, category, imageUrl} | with_entries(select(.value != null)))
            + {versions: (
                reduce ($plugin.versions[] | {changelog, checksum, sourceUrl, targetAbi, timestamp, version} | with_entries(select(.value != null))) as $v
                  ({seen: ($existing.versions // [] | map({key: compareKey, value: true}) | from_entries), list: ($existing.versions // [])};
                    ($v | compareKey) as $k
                    | if .seen[$k] then .
                      else .seen[$k] = true | .list += [$known[$plugin.name][$k] // $v]
                      end)
                | .list
              )}
          ))
    # fetch-manifest.sh already drops targetAbis above our Jellyfin version, so the highest one
    # left is the best match. Ties (re-published releases) go to the newest timestamp.
    | map_values(.versions |= (
        group_by(.version) | map(max_by([(.targetAbi | pad4), (.timestamp // "")]))
        | sort_by(.version | split(".") | map(tonumber)) | reverse | .[0:10]
      ))
  ' "$workdir/manifest.json" >"$workdir/merged.json"

  # Hash new versions in parallel. Failed prefetches (usually due to 404 on sourceUrl) produce
  # no hash, and those versions are dropped below.
  mkdir -p "$workdir/hashes"
  export -f prefetch_one
  jq -r '[to_entries[] | .key as $name | .value.versions[] | select(.hash == null) | {sourceUrl, label: "\($name | tojson) \(.version | tojson)"}] | unique_by(.sourceUrl) | .[] | "\(.sourceUrl)\t\(.label)"' "$workdir/merged.json" >"$workdir/to-hash.tsv"
  local total
  total="$(wc -l <"$workdir/to-hash.tsv")"
  echo "Hashing $total new plugin versions with $concurrency parallel jobs..."
  local done_count=0 failed_count=0 status label
  while IFS=$'\t' read -r status label; do
    done_count=$((done_count + 1))
    if [ "$status" = failed ]; then
      failed_count=$((failed_count + 1))
      echo "[$done_count/$total] Failed to fetch, skipping: $label"
    else
      echo "[$done_count/$total] New or updated version found: $label"
    fi
  done < <(xargs -r -d '\n' -P "$concurrency" -I{} bash -c 'prefetch_one "$1" "$2"' _ {} "$workdir/hashes" <"$workdir/to-hash.tsv")
  echo "Hashed $((done_count - failed_count))/$total new plugin versions ($failed_count failed)"

  local hashes_file="$workdir/hashes.tsv"
  find "$workdir/hashes" -type f -exec cat {} + >"$hashes_file"

  # Sort the plugins, and each plugin's versions (newest first), for consistency
  jq -S --rawfile tsv "$hashes_file" '
    ($tsv | split("\n") | map(select(. != "") | split("\t") | {key: .[0], value: .[1]}) | from_entries) as $hashes
    | map_values(
        .versions |= (
          map(if .hash == null then (if $hashes[.sourceUrl] then . + {hash: $hashes[.sourceUrl]} else empty end) else . end)
          | sort_by(.version | split(".") | map(tonumber)) | reverse
        )
      )
  ' "$workdir/merged.json" >"$plugins_file"
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

# One pass over the manifest for every fromRepo entry, emitting: file, name, current version,
# current hash, latest version, latest sourceUrl, sourceUrl of the current version.
lookup_fromrepo_versions() {
  discover_fromrepo | jq -R -s -r --slurpfile manifest <(printf '%s' "$SOURCE_MANIFEST") '
    ($manifest[0] | group_by(.name) | map({key: .[0].name, value: [.[].versions[]]}) | from_entries) as $byName
    | split("\n")[] | select(. != "") | split("\t") as [$file, $name, $current, $hash]
    | ($byName[$name] // []) as $versions
    | (try ($versions | sort_by(.version | split(".") | map(tonumber)) | last) catch null) as $latest
    | [$file, $name, $current, $hash]
      + if $latest.sourceUrl == null then []
        else [$latest.version, $latest.sourceUrl, ([$versions[] | select(.version == $current) | .sourceUrl] | first // "")]
        end
    | @tsv'
}

while IFS=$'\t' read -r nix_file plugin_name current_version current_hash latest_version source_url old_source_url; do
  if [[ -z "$latest_version" ]]; then
    echo "  $plugin_name: not found in manifest, skipping"
    continue
  fi

  if [[ "$latest_version" == "$current_version" ]]; then
    echo "  $plugin_name: already at $current_version"
    continue
  fi

  new_hash=$(nix flake prefetch --json "$source_url" 2>/dev/null | jq -r '.hash')

  echo "  $plugin_name: $current_version → $latest_version"
  sed -i "s|version = \"${current_version}\"|version = \"${latest_version}\"|g" "$nix_file"
  sed -i "s|${current_hash}|${new_hash}|g" "$nix_file"

  # Fixture manifests may embed the old sourceUrl literally; keep it in sync.
  if [[ -n "$old_source_url" && "$old_source_url" != "$source_url" ]]; then
    sed -i "s|${old_source_url}|${source_url}|g" "$nix_file"
  fi

  # Propagate the plugin directory name into any tests asserting on it.
  find "$REPO_ROOT" -name "*.nix" -not -path "*/.git/*" \
    -exec sed -i "s|${plugin_name}_${current_version}|${plugin_name}_${latest_version}|g" {} \;

done < <(lookup_fromrepo_versions)

echo ""
echo "Done."

{
  lib,
  pkgs,
  cfg,
}:
curlAuthArgs:
pkgs.writeShellScript "seerr-library-sync" ''
  echo "Fetching library list from Jellyfin..."
  LIBRARIES_RESPONSE=$(${pkgs.curl}/bin/curl -sf -X POST \
    ${curlAuthArgs} \
    "$BASE_URL/api/v1/settings/jellyfin/library/sync")

  echo "Available libraries:"
  echo "$LIBRARIES_RESPONSE" | ${pkgs.jq}/bin/jq -r '.[] | "\(.id) - \(.name) (\(.type))"'

  ${
    if cfg.jellyfin.enableAllLibraries then
      ''
        LIBRARY_IDS=$(echo "$LIBRARIES_RESPONSE" | ${pkgs.jq}/bin/jq -r '[.[].id] | join(",")')
      ''
    else
      ''
        LIBRARY_IDS=$(echo "$LIBRARIES_RESPONSE" | ${pkgs.jq}/bin/jq -r \
          --argjson types ${lib.escapeShellArg (builtins.toJSON cfg.jellyfin.libraryFilter.types)} \
          --argjson names ${lib.escapeShellArg (builtins.toJSON cfg.jellyfin.libraryFilter.names)} \
          '[ .[]
             | select(($types | length) == 0 or (.type | IN($types[])))
             | select(($names | length) == 0 or (.name | IN($names[])))
             | .id ] | join(",")')
      ''
  }

  if [ -n "$LIBRARY_IDS" ]; then
    echo "Enabling libraries: $LIBRARY_IDS"
    echo "$LIBRARIES_RESPONSE" | ${pkgs.jq}/bin/jq -r \
      --arg enableIds "$LIBRARY_IDS" \
      '($enableIds | split(",")) as $enabled | .[] | .id as $id | "\($id) \($enabled | index($id) != null)"' |
    while read -r LIB_ID LIB_ENABLED; do
      BODY=$(${pkgs.jq}/bin/jq -n --argjson enabled "$LIB_ENABLED" '{enabled: $enabled}')
      ${pkgs.curl}/bin/curl -sf -X PUT \
        ${curlAuthArgs} \
        -H "Content-Type: application/json" \
        -d "$BODY" \
        "$BASE_URL/api/v1/settings/jellyfin/library/$LIB_ID" >/dev/null
    done
    echo "Libraries enabled successfully"
  else
    echo "Warning: No libraries matched the filter criteria"
  fi
''

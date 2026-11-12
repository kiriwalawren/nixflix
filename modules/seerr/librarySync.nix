{
  lib,
  pkgs,
  cfg,
}:
{
  apiKey ? null,
  extraArgs ? "",
}:
let
  mkSecureCurl = import ../../lib/mk-secure-curl.nix { inherit lib pkgs; };
  syncMode = import ../../lib/sync-mode.nix { inherit lib pkgs; };
  mode = cfg.syncMode.jellyfinLibraries;

  # Libraries the delete-mode loop below would switch from enabled to disabled.
  toDisable = syncMode.mkPrune {
    inherit mode;
    unit = "seerr-libraries";
    what = "enabled Jellyfin libraries";
    option = "nixflix.seerr.syncMode.jellyfinLibraries";
    live = "LIBRARIES_TO_DISABLE";
    declared = [ ];
    key = ".id";
    label = ".name";
    onDelete = "";
  };

  enableLibraries =
    if mode == "delete" || cfg.jellyfin.enableAllLibraries then
      ''
        if [ -n "$LIBRARY_IDS" ]; then
          echo "Enabling libraries: $LIBRARY_IDS"
          echo "$LIBRARIES_RESPONSE" | ${pkgs.jq}/bin/jq -r \
            --arg enableIds "$LIBRARY_IDS" \
            '($enableIds | split(",")) as $enabled | .[] | .id as $id | "\($id) \($enabled | index($id) != null)"' |
          while read -r LIB_ID LIB_ENABLED; do
            BODY=$(${pkgs.jq}/bin/jq -n --argjson enabled "$LIB_ENABLED" '{enabled: $enabled}')
            ENABLE_HTTP_CODE=$(printf '%s' "$BODY" | ${
              mkSecureCurl apiKey {
                url = "$BASE_URL/api/v1/settings/jellyfin/library/$LIB_ID";
                method = "PUT";
                headers."Content-Type" = "application/json";
                data = "@-";
                extraArgs = ''${extraArgs} -o /dev/null -w "%{http_code}"'';
              }
            })
            checkResponse "enable" "$ENABLE_HTTP_CODE"
          done
          echo "Libraries enabled successfully"
        else
          echo "Warning: No libraries matched the filter criteria"
        fi
      ''
    else
      # keep/refuse: only switch matching libraries on, never switch any off.
      ''
        if [ -n "$LIBRARY_IDS" ]; then
          LIBRARIES_TO_DISABLE=$(echo "$LIBRARIES_RESPONSE" | ${pkgs.jq}/bin/jq -c \
            --arg enableIds "$LIBRARY_IDS" \
            '($enableIds | split(",")) as $enabled | [ .[] | select(.enabled == true) | select(.id as $id | $enabled | any(. == $id) | not) ]')
        else
          LIBRARIES_TO_DISABLE='[]'
        fi

        ${toDisable.guard}
        ${syncMode.refuseCheckpoint}
        ${toDisable.prune}
        if [ -n "$LIBRARY_IDS" ]; then
          echo "Enabling libraries: $LIBRARY_IDS"
          echo "$LIBRARIES_RESPONSE" | ${pkgs.jq}/bin/jq -r \
            --arg enableIds "$LIBRARY_IDS" \
            '($enableIds | split(",")) as $enabled | .[] | select(.id as $id | $enabled | any(. == $id)) | .id' |
          while read -r LIB_ID; do
            ENABLE_HTTP_CODE=$(printf '%s' '{"enabled":true}' | ${
              mkSecureCurl apiKey {
                url = "$BASE_URL/api/v1/settings/jellyfin/library/$LIB_ID";
                method = "PUT";
                headers."Content-Type" = "application/json";
                data = "@-";
                extraArgs = ''${extraArgs} -o /dev/null -w "%{http_code}"'';
              }
            })
            checkResponse "enable" "$ENABLE_HTTP_CODE"
          done
          echo "Libraries enabled successfully"
        else
          echo "Warning: No libraries matched the filter criteria"
        fi
      '';
in
pkgs.writeShellScript "seerr-library-sync" ''
  # Report the endpoint's status rather than exiting on a bare `curl -f` code.
  # Seerr below 3.5.0 404s on these routes and `nixflix.seerr` asserts against
  # that, but a mismatch still has to name itself in the journal.
  checkResponse() {
    if [ "$2" != "200" ] && [ "$2" != "201" ] && [ "$2" != "204" ]; then
      echo "Failed to $1 Jellyfin libraries (HTTP $2)" >&2
      echo "Seerr ${cfg.package.version} is configured." >&2
      exit 1
    fi
  }

  echo "Fetching library list from Jellyfin..."
  FETCH_RESPONSE=$(${
    mkSecureCurl apiKey {
      url = "$BASE_URL/api/v1/settings/jellyfin/library/sync";
      method = "POST";
      extraArgs = ''${extraArgs} -w "\n%{http_code}"'';
    }
  })

  FETCH_HTTP_CODE=$(echo "$FETCH_RESPONSE" | tail -n1)
  LIBRARIES_RESPONSE=$(echo "$FETCH_RESPONSE" | head -n-1)

  checkResponse "fetch" "$FETCH_HTTP_CODE"

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

  ${enableLibraries}''

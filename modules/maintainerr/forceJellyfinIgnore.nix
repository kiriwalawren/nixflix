{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix.maintainerr;
  secrets = import ../../lib/secrets { inherit lib; };

  maintainerrUrl = "http://${cfg.connectionAddress}:${toString cfg.port}";

  mkSonarrSeriesScript =
    server:
    let
      apiKeyVal = secrets.toShellValue server.apiKey;
    in
    ''
      echo "  Fetching series from ${server.serverName}..."
      SONARR_API_KEY=${apiKeyVal}
      ${pkgs.curl}/bin/curl -sf \
        -H "X-Api-Key: $SONARR_API_KEY" \
        "${server.url}/api/v3/series" \
        | ${pkgs.jq}/bin/jq -r '.[].path' >> "$SONARR_PATHS_FILE" \
        || echo "  Warning: failed to fetch series from ${server.serverName}" >&2
    '';
in
{
  config =
    mkIf (config.nixflix.enable && cfg.enable && cfg.settings.forceJellyfinToIgnoreEmptyMediaFolders)
      {
        nixflix.maintainerr.rules = [
          {
            name = "Shows To Ignore";
            description = "Creates list of shows that should be ignore because their folders are empty, but they are not ended.";
            library = "Shows";
            dataType = "show";
            arrAction = 4;
            sonarrServerName = "Sonarr";
            rules = [
              {
                customVal = {
                  ruleTypeId = 0;
                  value = "0";
                };
                firstVal = [
                  2
                  1
                ];
                action = 2;
                section = 0;
              }
              {
                customVal = {
                  ruleTypeId = 3;
                  value = "0";
                };
                operator = "0";
                firstVal = [
                  2
                  7
                ];
                action = 2;
                section = 0;
              }
              {
                operator = "0";
                firstVal = [
                  6
                  40
                ];
                action = 19;
                section = 1;
              }
            ];
          }
          {
            name = "Anime To Ignore";
            description = "Creates list of shows that should be ignore because their folders are empty, but they are not ended.";
            library = "Anime";
            dataType = "show";
            arrAction = 4;
            sonarrServerName = "Sonarr Anime";
            rules = [
              {
                firstVal = [
                  2
                  1
                ];
                action = 19;
                section = 0;
              }
              {
                customVal = {
                  ruleTypeId = 3;
                  value = "0";
                };
                operator = "0";
                firstVal = [
                  2
                  7
                ];
                action = 2;
                section = 0;
              }
              {
                operator = "0";
                firstVal = [
                  6
                  40
                ];
                action = 19;
                section = 1;
              }
            ];
          }
        ];
        systemd.timers.maintainerr-jellyfin-ignore = {
          description = "Manage Jellyfin .ignore files for empty media folders";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "5min";
            OnUnitActiveSec = "30min";
            Unit = "maintainerr-jellyfin-ignore.service";
          };
        };

        systemd.services.maintainerr-jellyfin-ignore = {
          description = "Add and remove .ignore files for empty Jellyfin media folders";
          after = [ "maintainerr-rules.service" ];
          wants = [ "maintainerr-rules.service" ];

          serviceConfig = {
            Type = "oneshot";
            ProtectSystem = "strict";
            ProtectHome = true;
            ReadWritePaths = [ config.nixflix.mediaDir ];
            PrivateTmp = true;
            ExecStart = pkgs.writeShellScript "maintainerr-jellyfin-ignore" (
              ''
                set -euo pipefail

                JELLYFIN_URL=${secrets.toShellValue cfg.settings.jellyfin.jellyfin_url}
                JELLYFIN_API_KEY=${secrets.toShellValue cfg.settings.jellyfin.jellyfin_api_key}

                IGNORE_PATHS_FILE=$(mktemp)
                SONARR_PATHS_FILE=$(mktemp)
                trap 'rm -f "$IGNORE_PATHS_FILE" "$SONARR_PATHS_FILE"' EXIT

                COLLECTIONS_FOUND=0

                echo "Fetching Maintainerr collections..."
                COLLECTIONS=$(${pkgs.curl}/bin/curl -sf "${maintainerrUrl}/api/collections")

                process_collection() {
                  local collection_name="$1"
                  local COLLECTION_ID COLLECTION_MEDIA MEDIA_SERVER_ID ITEM_PATH

                  COLLECTION_ID=$(echo "$COLLECTIONS" | ${pkgs.jq}/bin/jq -r \
                    --arg name "$collection_name" \
                    '[.[] | select(.title == $name) | .id] | .[0] // empty')

                  if [ -z "$COLLECTION_ID" ]; then
                    echo "Collection '$collection_name' not found in Maintainerr, skipping..."
                    return 0
                  fi

                  COLLECTIONS_FOUND=$((COLLECTIONS_FOUND + 1))
                  echo "Processing collection '$collection_name' (id=$COLLECTION_ID)..."

                  COLLECTION_MEDIA=$(${pkgs.curl}/bin/curl -sf \
                    "${maintainerrUrl}/api/collections/media/$COLLECTION_ID/content/1?size=300")

                  while IFS= read -r MEDIA_SERVER_ID; do
                    [ -z "$MEDIA_SERVER_ID" ] && continue

                    ITEM_PATH=$(${pkgs.curl}/bin/curl -sf \
                      -H "X-Emby-Token: $JELLYFIN_API_KEY" \
                      "$JELLYFIN_URL/Items/$MEDIA_SERVER_ID?Fields=Path" \
                      | ${pkgs.jq}/bin/jq -r '.Path // empty') || {
                      echo "  Warning: failed to get path for Jellyfin item $MEDIA_SERVER_ID" >&2
                      continue
                    }

                    if [ -n "$ITEM_PATH" ] && [ -d "$ITEM_PATH" ]; then
                      echo "  Adding .ignore to: $ITEM_PATH"
                      touch "$ITEM_PATH/.ignore"
                      echo "$ITEM_PATH" >> "$IGNORE_PATHS_FILE"
                    else
                      echo "  Warning: path not found or not a directory for Jellyfin item $MEDIA_SERVER_ID" >&2
                    fi
                  done < <(echo "$COLLECTION_MEDIA" | ${pkgs.jq}/bin/jq -r \
                    '.items[] | select(.mediaServerId != null) | .mediaServerId')
                }

                process_collection "Shows To Ignore"
                process_collection "Anime To Ignore"

                if [ "$COLLECTIONS_FOUND" -eq 0 ]; then
                  echo "No ignore collections found in Maintainerr; skipping cleanup."
                  exit 0
                fi

                echo "Collecting all Sonarr series paths for cleanup..."
              ''
              + concatMapStrings mkSonarrSeriesScript cfg.settings.sonarr
              + ''

                echo "Removing stale .ignore files..."
                while IFS= read -r SERIES_PATH; do
                  [ -z "$SERIES_PATH" ] && continue
                  if [ -f "$SERIES_PATH/.ignore" ]; then
                    if ! ${pkgs.gnugrep}/bin/grep -qxF "$SERIES_PATH" "$IGNORE_PATHS_FILE"; then
                      echo "  Removing stale .ignore from: $SERIES_PATH"
                      rm -f "$SERIES_PATH/.ignore"
                    fi
                  fi
                done < "$SONARR_PATHS_FILE"

                echo "Jellyfin ignore file management complete."
              ''
            );
          };
        };
      };
}

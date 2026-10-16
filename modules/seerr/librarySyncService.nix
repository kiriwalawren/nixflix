{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  inherit (config) nixflix;
  cfg = nixflix.seerr;
  authUtil = import ./authUtil.nix { inherit lib pkgs cfg; };
  baseUrl = "http://${cfg.connectionAddress}:${toString cfg.port}";
in
{
  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.services.seerr-libraries = {
      description = "Sync Seerr library selections";
      after = [
        "seerr-jellyfin.service"
      ]
      ++ optional nixflix.jellyfin.enable "jellyfin-libraries.service";
      requires = [
        "seerr-jellyfin.service"
      ]
      ++ optional nixflix.jellyfin.enable "jellyfin-libraries.service";
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -euo pipefail

        BASE_URL="${baseUrl}"

        # Authenticate
        source ${authUtil.authScript}

        # Fetch library list
        echo "Fetching library list from Jellyfin..."
        LIBRARIES_RESPONSE=$(${pkgs.curl}/bin/curl -sf \
          ${authUtil.curlAuthArgs} \
          "$BASE_URL/api/v1/settings/jellyfin/library?sync=true")

        echo "Available libraries:"
        echo "$LIBRARIES_RESPONSE" | ${pkgs.jq}/bin/jq -r '.[] | "\(.id) - \(.name) (\(.type))"'

        # Apply filters and get IDs to enable
        ${
          if cfg.jellyfin.enableAllLibraries then
            ''
              # Enable all libraries
              LIBRARY_IDS=$(echo "$LIBRARIES_RESPONSE" | ${pkgs.jq}/bin/jq -r '[.[].id] | join(",")')
            ''
          else
            ''
              # Apply filters to select libraries
              LIBRARY_IDS=$(echo "$LIBRARIES_RESPONSE" | ${pkgs.jq}/bin/jq -r \
                --argjson types ${escapeShellArg (builtins.toJSON cfg.jellyfin.libraryFilter.types)} \
                --argjson names ${escapeShellArg (builtins.toJSON cfg.jellyfin.libraryFilter.names)} \
                '[ .[]
                   | select(($types | length) == 0 or (.type | IN($types[])))
                   | select(($names | length) == 0 or (.name | IN($names[])))
                   | .id ] | join(",")')
            ''
        }

        if [ -n "$LIBRARY_IDS" ]; then
          echo "Enabling libraries: $LIBRARY_IDS"
          ${pkgs.curl}/bin/curl -sf \
            ${authUtil.curlAuthArgs} \
            "$BASE_URL/api/v1/settings/jellyfin/library?enable=$LIBRARY_IDS" >/dev/null
          echo "Libraries enabled successfully"
        else
          echo "Warning: No libraries matched the filter criteria"
        fi
      '';
    };
  };
}

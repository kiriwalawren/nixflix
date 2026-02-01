{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  inherit (config) nixflix;
  cfg = nixflix.jellyseerr;
  jellyfinCfg = nixflix.jellyfin;
  authUtil = import ./authUtil.nix {inherit lib pkgs cfg jellyfinCfg;};
  baseUrl = "http://127.0.0.1:${toString cfg.port}";
in {
  config = mkIf (nixflix.enable && cfg.enable && nixflix.jellyfin.enable) {
    systemd.services.jellyseerr-libraries = {
      description = "Sync Jellyseerr library selections";
      after = ["jellyseerr-setup.service" "jellyseerr-jellyfin.service" "jellyfin-libraries.service"];
      requires = ["jellyseerr-setup.service" "jellyseerr-jellyfin.service" "jellyfin-libraries.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = let
        typeFilter =
          if cfg.jellyfin.libraryFilter.types == []
          then "true"
          else let
            typeList = map (t: ''"${t}"'') cfg.jellyfin.libraryFilter.types;
          in ''[.type] | inside([${concatStringsSep "," typeList}])'';

        nameFilter =
          if cfg.jellyfin.libraryFilter.names == []
          then "true"
          else let
            nameList = map (n: ''"${n}"'') cfg.jellyfin.libraryFilter.names;
          in ''[.name] | inside([${concatStringsSep "," nameList}])'';

        libraryFilterExpr = ''select(${typeFilter} and ${nameFilter})'';
      in ''
        set -euo pipefail

        BASE_URL="${baseUrl}"

        # Authenticate
        source ${authUtil.authScript}

        # Fetch library list
        echo "Fetching library list from Jellyfin..."
        LIBRARIES_RESPONSE=$(${pkgs.curl}/bin/curl -sf \
          -b "${authUtil.cookieFile}" \
          "$BASE_URL/api/v1/settings/jellyfin/library?sync=true")

        echo "Available libraries:"
        echo "$LIBRARIES_RESPONSE" | ${pkgs.jq}/bin/jq -r '.[] | "\(.id) - \(.name) (\(.type))"'

        # Apply filters and get IDs to enable
        ${
          if cfg.jellyfin.enableAllLibraries
          then ''
            # Enable all libraries
            LIBRARY_IDS=$(echo "$LIBRARIES_RESPONSE" | ${pkgs.jq}/bin/jq -r '.[].id' | paste -sd,)
          ''
          else ''
            # Apply filters to select libraries
            LIBRARY_IDS=$(echo "$LIBRARIES_RESPONSE" | ${pkgs.jq}/bin/jq -r \
              '.[] | ${libraryFilterExpr} | .id' | paste -sd,)
          ''
        }

        if [ -n "$LIBRARY_IDS" ]; then
          echo "Enabling libraries: $LIBRARY_IDS"
          ${pkgs.curl}/bin/curl -sf \
            -b "${authUtil.cookieFile}" \
            "$BASE_URL/api/v1/settings/jellyfin/library?enable=$LIBRARY_IDS" >/dev/null
          echo "Libraries enabled successfully"
        else
          echo "Warning: No libraries matched the filter criteria"
        fi
      '';
    };
  };
}

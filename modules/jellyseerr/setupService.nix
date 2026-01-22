{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  secrets = import ../lib/secrets {inherit lib;};
  inherit (config) nixflix;
  cfg = nixflix.jellyseerr;
  jellyfinCfg = nixflix.jellyfin;

  adminUsers = filterAttrs (_: user: user.policy.isAdministrator) jellyfinCfg.users;
  sortedAdminNames = sort (a: b: a < b) (attrNames adminUsers);
  firstAdminName = head sortedAdminNames;
  firstAdminUser = adminUsers.${firstAdminName};

  authUtil = import ./authUtil.nix {inherit lib pkgs cfg jellyfinCfg;};
  baseUrl = "http://127.0.0.1:${toString cfg.port}";
in {
  config = mkIf (nixflix.enable && cfg.enable && nixflix.jellyfin.enable) {
    systemd.tmpfiles.rules = [
      "d '/run/jellyseerr' 0750 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.jellyseerr-setup = {
      description = "Complete Jellyseerr initial setup with Jellyfin";
      after = ["jellyseerr.service" "jellyfin-setup-wizard.service"];
      requires = ["jellyseerr.service" "jellyfin-setup-wizard.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig =
        {
          Type = "oneshot";
          RemainAfterExit = true;
        }
        // optionalAttrs (firstAdminUser.password != null) {
          LoadCredential = "jellyfin-password:${
            if secrets.isSecretRef firstAdminUser.password
            then firstAdminUser.password._secret
            else pkgs.writeText "jellyfin-${firstAdminName}-password" firstAdminUser.password
          }";
        };

      script = ''
        set -euo pipefail

        BASE_URL="${baseUrl}"

        # Wait for Jellyseerr
        echo "Waiting for Jellyseerr..."
        for i in {1..60}; do
          if ${pkgs.curl}/bin/curl -sf "$BASE_URL/api/v1/status" >/dev/null 2>&1; then
            break
          fi
          sleep 1
        done

        # Check if already initialized
        STATUS_RESPONSE=$(${pkgs.curl}/bin/curl -s "$BASE_URL/api/v1/settings/public")
        IS_INITIALIZED=$(echo "$STATUS_RESPONSE" | ${pkgs.jq}/bin/jq -r '.initialized // false')

        if [ "$IS_INITIALIZED" = "true" ]; then
          echo "Jellyseerr is already initialized"
          source ${authUtil.authScript}
          exit 0
        fi

        echo "Running initial setup..."

        # Step 1: Connect to Jellyfin (this creates the session cookie)
        # Use Jellyfin's first admin credentials
        ${
          if firstAdminUser.password != null
          then ''JELLYFIN_PASSWORD=$(cat "$CREDENTIALS_DIRECTORY/jellyfin-password")''
          else ''JELLYFIN_PASSWORD=""''
        }

        SETUP_PAYLOAD=$(${pkgs.jq}/bin/jq -n \
          --arg username "${firstAdminName}" \
          --arg password "$JELLYFIN_PASSWORD" \
          --arg hostname "${cfg.jellyfin.hostname}" \
          --arg port "${toString cfg.jellyfin.port}" \
          --arg useSsl "${boolToString cfg.jellyfin.useSsl}" \
          --arg urlBase "${cfg.jellyfin.urlBase}" \
          --arg email "${firstAdminUser.email or firstAdminName}" \
          --arg serverType "${toString cfg.jellyfin.serverType}" \
          '{
            username: $username,
            password: $password,
            hostname: $hostname,
            port: ($port | tonumber),
            useSsl: ($useSsl == "true"),
            urlBase: $urlBase,
            email: $email,
            serverType: ($serverType | tonumber)
          }')

        echo "Connecting to Jellyfin..."
        SETUP_RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST \
          -c "${authUtil.cookieFile}" \
          -H "Content-Type: application/json" \
          -d "$SETUP_PAYLOAD" \
          -w "\n%{http_code}" \
          "$BASE_URL/api/v1/auth/jellyfin")

        SETUP_HTTP_CODE=$(echo "$SETUP_RESPONSE" | tail -n1)

        if [ "$SETUP_HTTP_CODE" != "200" ] && [ "$SETUP_HTTP_CODE" != "201" ]; then
          echo "Failed to connect to Jellyfin (HTTP $SETUP_HTTP_CODE)" >&2
          echo "$SETUP_RESPONSE" | head -n-1 >&2
          exit 1
        fi

        chmod 600 "${authUtil.cookieFile}"
        echo "Successfully connected to Jellyfin"

        # Step 2: Fetch and enable libraries BEFORE sync
        echo "Fetching library list from Jellyfin..."
        LIBRARIES_RESPONSE=$(${pkgs.curl}/bin/curl -sf \
          -b "${authUtil.cookieFile}" \
          "$BASE_URL/api/v1/settings/jellyfin/library?sync=true")

        echo "Available libraries:"
        echo "$LIBRARIES_RESPONSE" | ${pkgs.jq}/bin/jq -r '.[] | "\(.id) - \(.name) (\(.type))"'

        # Apply library filters and get IDs to enable
        ${
          if cfg.jellyfin.enableAllLibraries
          then ''
            # Enable all libraries
            LIBRARY_IDS=$(echo "$LIBRARIES_RESPONSE" | ${pkgs.jq}/bin/jq -r '.[].id' | paste -sd,)
          ''
          else let
            # Build jq filter for library selection
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
          echo "Libraries enabled"
        else
          echo "Warning: No libraries matched the filter criteria"
        fi

        # Step 3: Complete initialization steps
        echo "Syncing with Jellyfin..."
        SYNC_RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST \
          -b "${authUtil.cookieFile}" \
          -H "Content-Type: application/json" \
          -w "\n%{http_code}" \
          "$BASE_URL/api/v1/settings/jellyfin/sync")

        SYNC_HTTP_CODE=$(echo "$SYNC_RESPONSE" | tail -n1)
        if [ "$SYNC_HTTP_CODE" != "200" ] && [ "$SYNC_HTTP_CODE" != "201" ] && [ "$SYNC_HTTP_CODE" != "204" ]; then
          echo "Failed to sync with Jellyfin (HTTP $SYNC_HTTP_CODE)" >&2
          echo "$SYNC_RESPONSE" | head -n-1 >&2
          exit 1
        fi

        echo "Initializing settings..."
        INIT_RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST \
          -b "${authUtil.cookieFile}" \
          -H "Content-Type: application/json" \
          -w "\n%{http_code}" \
          "$BASE_URL/api/v1/settings/initialize")

        INIT_HTTP_CODE=$(echo "$INIT_RESPONSE" | tail -n1)
        if [ "$INIT_HTTP_CODE" != "200" ] && [ "$INIT_HTTP_CODE" != "201" ] && [ "$INIT_HTTP_CODE" != "204" ]; then
          echo "Failed to initialize settings (HTTP $INIT_HTTP_CODE)" >&2
          echo "$INIT_RESPONSE" | head -n-1 >&2
          exit 1
        fi

        echo "Setting locale..."
        LOCALE_RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST \
          -b "${authUtil.cookieFile}" \
          -H "Content-Type: application/json" \
          -d '{"locale":"en"}' \
          -w "\n%{http_code}" \
          "$BASE_URL/api/v1/settings/main")

        LOCALE_HTTP_CODE=$(echo "$LOCALE_RESPONSE" | tail -n1)
        if [ "$LOCALE_HTTP_CODE" != "200" ] && [ "$LOCALE_HTTP_CODE" != "201" ] && [ "$LOCALE_HTTP_CODE" != "204" ]; then
          echo "Failed to set locale (HTTP $LOCALE_HTTP_CODE)" >&2
          echo "$LOCALE_RESPONSE" | head -n-1 >&2
          exit 1
        fi

        source ${authUtil.authScript}
        echo "Jellyseerr setup completed successfully"
      '';
    };
  };
}

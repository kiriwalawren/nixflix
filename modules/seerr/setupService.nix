{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  inherit (config) nixflix;
  cfg = nixflix.seerr;

  authUtil = import ./authUtil.nix { inherit lib pkgs cfg; };
  librarySync = import ./librarySync.nix { inherit lib pkgs cfg; };
  baseUrl = "http://${cfg.connectionAddress}:${toString cfg.port}";
  jqSetupSecrets = secrets.mkJqSecretArgs { password = cfg.jellyfin.adminPassword; };
in
{
  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.services.seerr-setup = {
      description = "Complete Seerr initial setup with Jellyfin";
      after = [ "seerr.service" ] ++ optional nixflix.jellyfin.enable "jellyfin-setup-wizard.service";
      requires = [ "seerr.service" ] ++ optional nixflix.jellyfin.enable "jellyfin-setup-wizard.service";
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -euo pipefail

        BASE_URL="${baseUrl}"

        echo "Waiting for Seerr..."
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
          echo "Seerr is already initialized"
          source ${authUtil.authScript}
          exit 0
        fi

        echo "Running initial setup..."

        # Step 1: Connect to Jellyfin (this creates the session cookie)
        SETUP_PAYLOAD=$(${pkgs.jq}/bin/jq -n \
          ${jqSetupSecrets.flagsString} \
          --arg username "${cfg.jellyfin.adminUsername}" \
          --arg hostname "${cfg.jellyfin.hostname}" \
          --arg port "${toString cfg.jellyfin.port}" \
          --arg useSsl "${boolToString cfg.jellyfin.useSsl}" \
          --arg urlBase "${cfg.jellyfin.urlBase}" \
          --arg email "${cfg.jellyfin.adminUsername}" \
          --arg serverType "${toString cfg.jellyfin.serverType}" \
          '{
            username: $username,
            password: ${jqSetupSecrets.refs.password},
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
        SETUP_BODY=$(echo "$SETUP_RESPONSE" | head -n-1)

        if [ "$SETUP_HTTP_CODE" != "200" ] && [ "$SETUP_HTTP_CODE" != "201" ]; then
          SETUP_ERROR=$(echo "$SETUP_BODY" | ${pkgs.jq}/bin/jq -r '.error // empty')

          if [ "$SETUP_ERROR" = "Jellyfin hostname already configured" ]; then
            # Seerr persists the hostname before later steps run; retry without it to re-login.
            echo "Jellyfin hostname already configured from a previous run; retrying login..."
            RETRY_PAYLOAD=$(echo "$SETUP_PAYLOAD" | ${pkgs.jq}/bin/jq 'del(.hostname)')

            SETUP_RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST \
              -c "${authUtil.cookieFile}" \
              -H "Content-Type: application/json" \
              -d "$RETRY_PAYLOAD" \
              -w "\n%{http_code}" \
              "$BASE_URL/api/v1/auth/jellyfin")

            SETUP_HTTP_CODE=$(echo "$SETUP_RESPONSE" | tail -n1)
            SETUP_BODY=$(echo "$SETUP_RESPONSE" | head -n-1)
          fi
        fi

        if [ "$SETUP_HTTP_CODE" != "200" ] && [ "$SETUP_HTTP_CODE" != "201" ]; then
          echo "Failed to connect to Jellyfin (HTTP $SETUP_HTTP_CODE)" >&2
          echo "$SETUP_BODY" >&2
          exit 1
        fi

        chmod 600 "${authUtil.cookieFile}"
        echo "Successfully connected to Jellyfin"

        # Step 2: Fetch and enable libraries BEFORE sync
        source ${librarySync ''-b "${authUtil.cookieFile}"''}

        # Step 3: Complete initialization steps
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

        echo "Syncing with Jellyfin..."
        SYNC_RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST \
          -b "${authUtil.cookieFile}" \
          -H "Content-Type: application/json" \
          -w "\n%{http_code}" \
          "$BASE_URL/api/v1/settings/jellyfin/sync")

        SYNC_HTTP_CODE=$(echo "$SYNC_RESPONSE" | tail -n1)
        if [ "$SYNC_HTTP_CODE" != "200" ] && [ "$SYNC_HTTP_CODE" != "201" ] && [ "$SYNC_HTTP_CODE" != "204" ]; then
          # Non-fatal: Jellyseerr may return 500 on first sync if the scan job
          # hasn't initialized yet. The sync runs on schedule regardless.
          echo "Warning: Jellyfin sync returned HTTP $SYNC_HTTP_CODE, continuing..."
          echo "$SYNC_RESPONSE" | head -n-1
        fi

        source ${authUtil.authScript}
        echo "Seerr setup completed successfully"
      '';
    };
  };
}

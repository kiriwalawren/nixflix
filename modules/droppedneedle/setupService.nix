{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  getFirstAdmin = import ../../lib/getFirstAdmin.nix { inherit lib; };
  inherit (config) nixflix;
  cfg = nixflix.droppedneedle;

  firstAdmin = getFirstAdmin {
    users = cfg.settings.users;
    isAdmin = user: user.role == "admin";
  };
  firstAdminUser = firstAdmin.user;
  firstAdminUserName = firstAdminUser.userName;
  firstAdminDisplayName = firstAdmin.name;
  firstAdminEmail = if firstAdminUser.email == null then "" else firstAdminUser.email;

  jqAdminSecrets = secrets.mkJqSecretArgs {
    inherit (firstAdminUser) password;
  };

  baseUrl = "http://${cfg.connectionAddress}:${toString cfg.port}";
  apiUrl = "${baseUrl}/api/v1";
in
{
  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.services.droppedneedle-create-admin = {
      description = "Create first DroppedNeedle admin user";
      after = [ "droppedneedle.service" ];
      requires = [ "droppedneedle.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -eu

        BASE_URL="${baseUrl}"
        API_URL="${apiUrl}"

        # During its one-time first-boot library migration, DroppedNeedle runs a
        # stand-in health server that answers /health with HTTP 200 and
        # {"status":"upgrading"} while returning 503 for every other path
        # (maintenance/automatic_upgrade.py: _UpgradeHealthHandler). The real
        # app only takes over once that finishes, so readiness requires
        # status == "ok", not just a 200 - matching the app's own internal
        # readiness check (automatic_upgrade.py: is_healthy()).
        echo "Waiting for DroppedNeedle to be ready..."
        for i in {1..300}; do
          HEALTH_BODY=$(${pkgs.curl}/bin/curl --connect-timeout 5 --max-time 10 -s "$BASE_URL/health" 2>/dev/null || echo "")
          if [ -n "$HEALTH_BODY" ] && [ "$(echo "$HEALTH_BODY" | ${pkgs.jq}/bin/jq -r '.status // empty' 2>/dev/null)" = "ok" ]; then
            break
          fi
          if [ "$i" -eq 300 ]; then
            echo "Timeout waiting for DroppedNeedle after 300 attempts" >&2
            exit 1
          fi
          sleep 1
        done

        STATUS_RESPONSE=$(${pkgs.curl}/bin/curl -s -w "\n%{http_code}" "$API_URL/auth/setup/status")
        STATUS_HTTP_CODE=$(echo "$STATUS_RESPONSE" | tail -n1)
        STATUS_BODY=$(echo "$STATUS_RESPONSE" | sed '$d')

        if [ "$STATUS_HTTP_CODE" -lt 200 ] || [ "$STATUS_HTTP_CODE" -ge 300 ]; then
          echo "Failed to query DroppedNeedle setup status (HTTP $STATUS_HTTP_CODE): $STATUS_BODY" >&2
          exit 1
        fi

        SETUP_REQUIRED=$(echo "$STATUS_BODY" | ${pkgs.jq}/bin/jq -r '.required')

        if [ "$SETUP_REQUIRED" != "true" ]; then
          echo "DroppedNeedle setup already completed, skipping"
          exit 0
        fi

        echo "Creating first admin user: ${firstAdminUserName}"

        SETUP_PAYLOAD=$(${pkgs.jq}/bin/jq -n \
          ${jqAdminSecrets.flagsString} \
          --arg displayName ${escapeShellArg firstAdminDisplayName} \
          --arg username ${escapeShellArg firstAdminUserName} \
          --arg email ${escapeShellArg firstAdminEmail} \
          '{display_name: $displayName, username: $username, email: $email, password: ${jqAdminSecrets.refs.password}}')

        RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST \
          -H "Content-Type: application/json" \
          -d "$SETUP_PAYLOAD" \
          -w "\n%{http_code}" \
          "$API_URL/auth/setup")

        HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
        BODY=$(echo "$RESPONSE" | sed '$d')

        if [ "$HTTP_CODE" = "409" ]; then
          echo "DroppedNeedle setup already completed, skipping creation"
        elif [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
          echo "Failed to create admin user ${firstAdminUserName} (HTTP $HTTP_CODE): $BODY" >&2
          exit 1
        else
          echo "Created admin user ${firstAdminUserName}"
        fi
      '';
    };
  };
}

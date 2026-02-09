{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  secrets = import ../lib/secrets { inherit lib; };
  inherit (config) nixflix;
  cfg = config.nixflix.jellyfin;

  authUtil = import ./authUtil.nix { inherit lib pkgs cfg; };

  adminUsers = filterAttrs (_: user: user.policy.isAdministrator) cfg.users;
  sortedAdminNames = sort (a: b: a < b) (attrNames adminUsers);
  firstAdminName = head sortedAdminNames;
  firstAdminUser = adminUsers.${firstAdminName};

  jqUserSecrets = secrets.mkJqSecretArgs {
    inherit (firstAdminUser) password;
  };

  baseUrl =
    if cfg.network.baseUrl == "" then
      "http://127.0.0.1:${toString cfg.network.internalHttpPort}"
    else
      "http://127.0.0.1:${toString cfg.network.internalHttpPort}/${cfg.network.baseUrl}";
in
{
  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.services.jellyfin-setup-wizard = {
      description = "Complete Jellyfin Setup Wizard";
      after = [ "jellyfin.service" ];
      requires = [ "jellyfin.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -eu

        BASE_URL="${baseUrl}"

        echo "Checking if first admin user needs to be created..."

        # Check if startup wizard is already completed via API
        SYSTEM_INFO=$(${pkgs.curl}/bin/curl -s "$BASE_URL/System/Info/Public")
        STARTUP_WIZARD_COMPLETED=$(echo "$SYSTEM_INFO" | ${pkgs.jq}/bin/jq -r '.StartupWizardCompleted // false')

        echo "IsStartupWizardCompleted: $STARTUP_WIZARD_COMPLETED"

        if [ "$STARTUP_WIZARD_COMPLETED" = "false" ]; then
          echo "Running Jellyfin setup wizard..."

          # Step 1: Set configuration
          echo "Setting initial configuration..."
          RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST \
            -H "Content-Type: application/json" \
            -d '{"ServerName":"${cfg.system.serverName}","UICulture":"${cfg.system.uiCulture}","MetadataCountryCode":"${cfg.system.metadataCountryCode}","PreferredMetadataLanguage":"${cfg.system.preferredMetadataLanguage}"}' \
            -w "\n%{http_code}" \
            "$BASE_URL/Startup/Configuration")

          HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
          BODY=$(echo "$RESPONSE" | sed '$d')

          echo "Configuration response (HTTP $HTTP_CODE): $BODY"

          if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
            echo "Failed to set configuration (HTTP $HTTP_CODE)" >&2
            exit 1
          fi

          # Step 2: Create first user
          echo "Creating first admin user: ${firstAdminName}"

          # Call GET first to initialize
          echo "Initializing user creation..."
          GET_RESPONSE=$(${pkgs.curl}/bin/curl -s -X GET \
            -w "\n%{http_code}" \
            "$BASE_URL/Startup/User")

          GET_HTTP_CODE=$(echo "$GET_RESPONSE" | tail -n1)
          GET_BODY=$(echo "$GET_RESPONSE" | sed '$d')

          echo "GET /Startup/User response (HTTP $GET_HTTP_CODE): $GET_BODY"

          USER_PAYLOAD=$(${pkgs.jq}/bin/jq -n \
            ${jqUserSecrets.flagsString} \
            --arg name "${firstAdminName}" \
            '{Name: $name, Password: ${jqUserSecrets.refs.password}}')

          RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "$USER_PAYLOAD" \
            -w "\n%{http_code}" \
            "$BASE_URL/Startup/User")

          HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
          BODY=$(echo "$RESPONSE" | sed '$d')

          echo "First user creation response (HTTP $HTTP_CODE): $BODY"

          if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
            echo "Failed to create first user ${firstAdminName} (HTTP $HTTP_CODE)" >&2
            exit 1
          fi

          # Step 3: Set remote access
          echo "Configuring remote access..."
          RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST \
            -H "Content-Type: application/json" \
            -d '{"EnableRemoteAccess":${boolToString cfg.network.enableRemoteAccess}}' \
            -w "\n%{http_code}" \
            "$BASE_URL/Startup/RemoteAccess")

          HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
          BODY=$(echo "$RESPONSE" | sed '$d')

          echo "Remote access response (HTTP $HTTP_CODE): $BODY"

          if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
            echo "Failed to configure remote access (HTTP $HTTP_CODE)" >&2
            exit 1
          fi

          # Step 4: Complete wizard
          echo "Completing setup wizard..."
          RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST \
            -w "\n%{http_code}" \
            "$BASE_URL/Startup/Complete")

          HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
          BODY=$(echo "$RESPONSE" | sed '$d')

          echo "Complete wizard response (HTTP $HTTP_CODE): $BODY"

          if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
            echo "Failed to complete setup wizard (HTTP $HTTP_CODE)" >&2
            exit 1
          fi

          echo "Jellyfin setup wizard completed successfully"
        else
          echo "Setup wizard already completed, skipping"
        fi

        echo "Waiting 3 seconds for database to stabilize after wizard completion..."
        sleep 3
        echo "Waiting for Jellyfin to be ready for authenticated requests..."
        source ${authUtil.authScript}
        echo "Waiting 2 seconds for Jellyfin to fully stabilize..."
        sleep 2
      '';
    };
  };
}

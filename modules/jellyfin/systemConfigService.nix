{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  inherit (config) nixflix;
  cfg = config.nixflix.jellyfin;

  util = import ./util.nix {inherit lib;};

  adminUsers = filterAttrs (_: user: user.policy.isAdministrator) cfg.users;
  sortedAdminNames = sort (a: b: a < b) (attrNames adminUsers);
  firstAdminName = head sortedAdminNames;
  firstAdminUser = adminUsers.${firstAdminName};

  systemConfig = util.recursiveTransform (removeAttrs cfg.system ["removeOldPlugins"]);

  systemConfigJson = builtins.toJSON systemConfig;

  systemConfigFile = pkgs.writeText "jellyfin-system-config.json" systemConfigJson;
in {
  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.services.jellyfin-system-config = {
      description = "Configure Jellyfin System Settings via API";
      after = ["jellyfin-setup-wizard.service"];
      wants = ["jellyfin-setup-wizard.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -eu

        BASE_URL="http://127.0.0.1:${toString cfg.network.internalHttpPort}${cfg.network.baseUrl}"

        echo "Configuring Jellyfin system settings..."

        echo "Authenticating as ${firstAdminName}..."
        ${
          if firstAdminUser.passwordFile != null
          then ''ADMIN_PASSWORD=$(${pkgs.coreutils}/bin/cat ${firstAdminUser.passwordFile})''
          else ''ADMIN_PASSWORD=""''
        }

        AUTH_RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST \
          -H "Content-Type: application/json" \
          -H 'Authorization: MediaBrowser Client="nixflix", Device="NixOS", DeviceId="nixflix-system-config", Version="1.0.0"' \
          -d "{\"Username\": \"${firstAdminName}\", \"Pw\": \"$ADMIN_PASSWORD\"}" \
          "$BASE_URL/Users/AuthenticateByName")

        echo "Auth response: $AUTH_RESPONSE"

        ACCESS_TOKEN=$(echo "$AUTH_RESPONSE" | ${pkgs.jq}/bin/jq -r '.AccessToken // empty' 2>/dev/null || echo "")

        if [ -z "$ACCESS_TOKEN" ]; then
          echo "Failed to authenticate as ${firstAdminName}" >&2
          echo "Auth response was not valid JSON or missing AccessToken" >&2
          exit 1
        fi

        echo "Successfully authenticated"

        RESPONSE=$(${pkgs.curl}/bin/curl -X POST \
          -H "Authorization: MediaBrowser Client=\"nixflix\", Device=\"NixOS\", DeviceId=\"nixflix-system-config\", Version=\"1.0.0\", Token=\"$ACCESS_TOKEN\"" \
          -H "Content-Type: application/json" \
          -d @${systemConfigFile} \
          -w "\n%{http_code}" \
          "$BASE_URL/System/Configuration")

        HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
        BODY=$(echo "$RESPONSE" | sed '$d')

        echo "System config response (HTTP $HTTP_CODE): $BODY"

        if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
          echo "Failed to configure Jellyfin system settings (HTTP $HTTP_CODE)" >&2
          exit 1
        fi

        echo "Jellyfin system configuration completed successfully"
      '';
    };
  };
}

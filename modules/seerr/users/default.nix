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
  mkSecureCurl = import ../../../lib/mk-secure-curl.nix { inherit lib pkgs; };
  baseUrl = "http://${cfg.connectionAddress}:${toString cfg.port}";
  userSettings = cfg.settings.users;
in
{
  imports = [ ./options.nix ];

  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.services.seerr-user-settings = {
      description = "Configure Seerr default user settings";
      after = [ "seerr-setup.service" ];
      requires = [ "seerr-setup.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script =
        let
          userSettingsJson = builtins.toJSON userSettings;
        in
        ''
          set -euo pipefail

          BASE_URL="${baseUrl}"

          echo "Configuring default user settings..."

          # POST user settings (endpoint accepts partial documents)
          SETTINGS_RESPONSE=$(printf '%s' ${escapeShellArg userSettingsJson} | ${
            mkSecureCurl cfg.apiKey {
              url = "$BASE_URL/api/v1/settings/main";
              method = "POST";
              headers."Content-Type" = "application/json";
              data = "@-";
              extraArgs = ''-w "\n%{http_code}"'';
            }
          })

          SETTINGS_HTTP_CODE=$(echo "$SETTINGS_RESPONSE" | tail -n1)
          if [ "$SETTINGS_HTTP_CODE" != "200" ] && [ "$SETTINGS_HTTP_CODE" != "201" ] && [ "$SETTINGS_HTTP_CODE" != "204" ]; then
            echo "Failed to configure user settings (HTTP $SETTINGS_HTTP_CODE)" >&2
            echo "$SETTINGS_RESPONSE" | head -n-1 >&2
            exit 1
          fi

          echo "User settings configured successfully"
        '';
    };
  };
}

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
in
{
  imports = [ ./options.nix ];

  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.services.seerr-jellyfin = {
      description = "Configure Jellyfin settings in Seerr";
      after = [ "seerr-user-settings.service" ];
      requires = [ "seerr-user-settings.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -euo pipefail

        BASE_URL="${baseUrl}"

        echo "Configuring default user settings..."

        # POST user settings (endpoint accepts partial documents)
        SETUP_PAYLOAD=$(${pkgs.jq}/bin/jq -n \
          --arg ip "${cfg.jellyfin.hostname}" \
          --arg port "${toString cfg.jellyfin.port}" \
          --arg useSsl "${boolToString cfg.jellyfin.useSsl}" \
          --arg urlBase "${cfg.jellyfin.urlBase}" \
          --arg externalHostname "${cfg.jellyfin.externalHostname}" \
          '{
            ip: $ip,
            port: ($port | tonumber),
            useSsl: ($useSsl == "true"),
            urlBase: $urlBase,
            externalHostname: $externalHostname
          }')

        SETTINGS_RESPONSE=$(printf '%s' "$SETUP_PAYLOAD" | ${
          mkSecureCurl cfg.apiKey {
            url = "$BASE_URL/api/v1/settings/jellyfin";
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

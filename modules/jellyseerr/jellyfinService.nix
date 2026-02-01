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
    systemd.services.jellyseerr-jellyfin = {
      description = "Configure Jellyfin settings in Jellyseerr";
      after = ["jellyseerr-user-settings.service"];
      requires = ["jellyseerr-user-settings.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -euo pipefail

        BASE_URL="${baseUrl}"

        # Authenticate
        source ${authUtil.authScript}

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

        SETTINGS_RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST \
          -b "${authUtil.cookieFile}" \
          -H "Content-Type: application/json" \
          -d "$SETUP_PAYLOAD" \
          -w "\n%{http_code}" \
          "$BASE_URL/api/v1/settings/jellyfin")

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

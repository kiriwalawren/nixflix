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
  authUtil = import ./authUtil.nix {inherit lib pkgs cfg;};

  systemConfig = util.recursiveTransform (removeAttrs cfg.system ["removeOldPlugins"]);

  systemConfigJson = builtins.toJSON systemConfig;

  systemConfigFile = pkgs.writeText "jellyfin-system-config.json" systemConfigJson;

  baseUrl =
    if cfg.network.baseUrl == ""
    then "http://127.0.0.1:${toString cfg.network.internalHttpPort}"
    else "http://127.0.0.1:${toString cfg.network.internalHttpPort}/${cfg.network.baseUrl}";
in {
  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.services.jellyfin-system-config = {
      description = "Configure Jellyfin System Settings via API";
      after = ["jellyfin-setup-wizard.service"];
      requires = ["jellyfin-setup-wizard.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -eu

        BASE_URL="${baseUrl}"

        echo "Configuring Jellyfin system settings..."

        source ${authUtil.authScript}

        RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST \
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

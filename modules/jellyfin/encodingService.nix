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

  # Transform encoding config to API format
  encodingConfig = util.recursiveTransform cfg.encoding;
  encodingConfigJson = builtins.toJSON encodingConfig;
  encodingConfigFile = pkgs.writeText "jellyfin-encoding-config.json" encodingConfigJson;
in {
  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.services.jellyfin-encoding-config = {
      description = "Configure Jellyfin Encoding via API";
      after = ["jellyfin-setup-wizard.service"];
      requires = ["jellyfin-setup-wizard.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -eu

        BASE_URL="http://127.0.0.1:${toString cfg.network.internalHttpPort}/${cfg.network.baseUrl}"

        echo "Configuring Jellyfin encoding settings..."

        source ${authUtil.authScript}

        echo "Updating encoding configuration..."

        RESPONSE=$(${pkgs.curl}/bin/curl -X POST \
          -H "Authorization: MediaBrowser Client=\"nixflix\", Device=\"NixOS\", DeviceId=\"nixflix-encoding-config\", Version=\"1.0.0\", Token=\"$ACCESS_TOKEN\"" \
          -H "Content-Type: application/json" \
          -d @${encodingConfigFile} \
          -w "\n%{http_code}" \
          "$BASE_URL/System/Configuration/encoding")

        HTTP_CODE=$(echo "$RESPONSE" | ${pkgs.coreutils}/bin/tail -n1)

        echo "Encoding config response (HTTP $HTTP_CODE)"

        if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
          echo "Failed to configure Jellyfin encoding settings (HTTP $HTTP_CODE)" >&2
          exit 1
        fi

        echo "Jellyfin encoding configuration completed successfully"
      '';
    };
  };
}

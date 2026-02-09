{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  inherit (config) nixflix;
  cfg = config.nixflix.jellyfin;

  util = import ./util.nix { inherit lib; };
  mkSecureCurl = import ../lib/mk-secure-curl.nix { inherit lib pkgs; };
  authUtil = import ./authUtil.nix { inherit lib pkgs cfg; };

  encodingConfig = util.recursiveTransform cfg.encoding;
  encodingConfigJson = builtins.toJSON encodingConfig;
  encodingConfigFile = pkgs.writeText "jellyfin-encoding-config.json" encodingConfigJson;

  baseUrl =
    if cfg.network.baseUrl == "" then
      "http://127.0.0.1:${toString cfg.network.internalHttpPort}"
    else
      "http://127.0.0.1:${toString cfg.network.internalHttpPort}/${cfg.network.baseUrl}";
in
{
  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.tmpfiles.rules = mkIf (cfg.encoding.transcodingTempPath != "") [
      "d '${cfg.encoding.transcodingTempPath}' 0755 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.jellyfin-encoding-config = {
      description = "Configure Jellyfin Encoding via API";
      after = [
        "jellyfin-setup-wizard.service"
        "systemd-tmpfiles-setup.service"
      ];
      requires = [ "jellyfin-setup-wizard.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -eu

        BASE_URL="${baseUrl}"

        echo "Configuring Jellyfin encoding settings..."

        source ${authUtil.authScript}

        echo "Updating encoding configuration..."

        RESPONSE=$(${
          mkSecureCurl authUtil.token {
            method = "POST";
            url = "$BASE_URL/System/Configuration/encoding";
            apiKeyHeader = "Authorization";
            headers = {
              "Content-Type" = "application/json";
            };
            data = "@${encodingConfigFile}";
            extraArgs = "-w \"\\n%{http_code}\"";
          }
        })

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

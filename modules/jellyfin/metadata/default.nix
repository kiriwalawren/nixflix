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

  util = import ../util.nix { inherit lib; };
  mkSecureCurl = import ../../../lib/mk-secure-curl.nix { inherit lib pkgs; };
  authUtil = import ../authUtil.nix { inherit lib pkgs cfg; };

  metadataConfigFile = pkgs.writeText "jellyfin-metadata-config.json" (
    builtins.toJSON (util.recursiveTransform cfg.metadata)
  );

  baseUrl =
    if cfg.network.baseUrl == "" then
      "http://${cfg.connectionAddress}:${toString cfg.network.internalHttpPort}"
    else
      "http://${cfg.connectionAddress}:${toString cfg.network.internalHttpPort}/${cfg.network.baseUrl}";

  waitForApiScript = import ../waitForApiScript.nix {
    inherit pkgs;
    jellyfinCfg = cfg;
  };
in
{
  imports = [ ./options.nix ];

  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.services.jellyfin-metadata-config = {
      description = "Configure Jellyfin Metadata Settings via API";
      after = [ "jellyfin-setup-wizard.service" ];
      requires = [ "jellyfin-setup-wizard.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = waitForApiScript;
      };

      script = ''
        set -eu

        BASE_URL="${baseUrl}"

        echo "Configuring Jellyfin metadata settings..."

        source ${authUtil.authScript}

        echo "Updating metadata configuration..."

        RESPONSE=$(${
          mkSecureCurl authUtil.token {
            method = "POST";
            url = "$BASE_URL/System/Configuration/metadata";
            apiKeyHeader = "Authorization";
            headers = {
              "Content-Type" = "application/json";
            };
            data = "@${metadataConfigFile}";
            extraArgs = "-w \"\\n%{http_code}\"";
          }
        })

        HTTP_CODE=$(echo "$RESPONSE" | ${pkgs.coreutils}/bin/tail -n1)

        echo "Metadata config response (HTTP $HTTP_CODE)"

        if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
          echo "Failed to configure Jellyfin metadata settings (HTTP $HTTP_CODE)" >&2
          exit 1
        fi

        echo "Jellyfin metadata configuration completed successfully"
      '';
    };
  };
}

{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  inherit (config) nixflix;
  cfg = nixflix.aurral;
  jfCfg = cfg.settings.jellyfin;

  apiUtil = import ./apiUtil.nix { inherit lib pkgs cfg; };
  inherit (apiUtil) apiCall;
  mkSecureCurl = import ../../lib/mk-secure-curl.nix { inherit lib pkgs; };
  jq = "${pkgs.jq}/bin/jq";

  jellyfinJq = secrets.mkJqSecretArgs { jellyfinApiKey = jfCfg.apiKey; };

  configureJellyfin = ''
    echo "Looking up Jellyfin user "${escapeShellArg jfCfg.userName}
    check_response "fetch Jellyfin users" "$(${
      mkSecureCurl jfCfg.apiKey {
        url = "${jfCfg.url}/Users";
        apiKeyHeader = "Authorization";
        apiKeyTemplate = ''MediaBrowser Client=\"nixflix\", Device=\"NixOS\", DeviceId=\"nixflix-aurral\", Version=\"1.0.0\", Token=\"{{apiKey:trim}}\"'';
        extraArgs = ''-w "\n%{http_code}"'';
      }
    })"
    USER_ID=$(echo "$BODY" | ${jq} -r --arg name ${escapeShellArg jfCfg.userName} \
      'first(.[] | select(.Name == $name) | .Id) // empty')
    if [ -z "$USER_ID" ]; then
      echo "Jellyfin user "${escapeShellArg jfCfg.userName}" not found" >&2
      exit 1
    fi

    echo "Saving Jellyfin connection..."
    PAYLOAD=$(${jq} -n \
      ${jellyfinJq.flagsString} \
      --arg url ${escapeShellArg jfCfg.url} \
      --arg userId "$USER_ID" \
      '{ integrations: { jellyfin: { url: $url, apiKey: ${jellyfinJq.refs.jellyfinApiKey}, userId: $userId } } }')
    check_response "save Jellyfin connection" "$(${apiCall "POST" "/settings" "$PAYLOAD"})"
  '';

  clearJellyfin = ''
    echo "Clearing Jellyfin integration..."
    check_response "clear Jellyfin" "$(${
      apiCall "POST" "/settings" ''{"integrations":{"jellyfin":{"url":"","apiKey":"","userId":""}}}''
    })"
  '';
in
{
  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.services.aurral-jellyfin = {
      description = "Configure Aurral's Jellyfin integration";
      after = [
        "aurral-setup.service"
      ]
      ++ optional (jfCfg.enable && nixflix.jellyfin.enable) "jellyfin-users-config.service";
      requires = [
        "aurral-setup.service"
      ]
      ++ optional (jfCfg.enable && nixflix.jellyfin.enable) "jellyfin-users-config.service";
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -euo pipefail

        ${apiUtil.preamble}

        ${if jfCfg.enable then configureJellyfin else clearJellyfin}
      '';
    };
  };
}

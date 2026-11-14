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
  ndCfg = cfg.settings.navidrome;

  apiUtil = import ./apiUtil.nix { inherit lib pkgs cfg; };
  inherit (apiUtil) apiCall;

  navidromeJq = secrets.mkJqSecretArgs { navidromePassword = ndCfg.password; };

  configureNavidrome = ''
    echo "Saving Navidrome connection..."
    PAYLOAD=$(${pkgs.jq}/bin/jq -n \
      ${navidromeJq.flagsString} \
      --arg url ${escapeShellArg ndCfg.url} \
      --arg username ${escapeShellArg ndCfg.username} \
      '{ integrations: { navidrome: { url: $url, username: $username, password: ${navidromeJq.refs.navidromePassword} } } }')
    check_response "save Navidrome connection" "$(${apiCall "POST" "/settings" "$PAYLOAD"})"
  '';

  clearNavidrome = ''
    echo "Clearing Navidrome integration..."
    check_response "clear Navidrome" "$(${
      apiCall "POST" "/settings" ''{"integrations":{"navidrome":{"url":"","username":"","password":""}}}''
    })"
  '';

  navidromeDeps = optional (ndCfg.enable && nixflix.navidrome.enable) "navidrome-libraries.service";
in
{
  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.services.aurral-navidrome = {
      description = "Configure Aurral's Navidrome integration";
      after = [ "aurral-setup.service" ] ++ navidromeDeps;
      requires = [ "aurral-setup.service" ] ++ navidromeDeps;
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -euo pipefail

        ${apiUtil.preamble}

        ${if ndCfg.enable && nixflix.navidrome.enable then configureNavidrome else clearNavidrome}
      '';
    };
  };
}

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
  sabCfg = cfg.settings.sabnzbd;
  sabnzbd = nixflix.usenetClients.sabnzbd;

  apiUtil = import ./apiUtil.nix { inherit lib pkgs cfg; };
  inherit (apiUtil) apiCall;

  sabJq = secrets.mkJqSecretArgs { sabnzbdApiKey = sabCfg.apiKey; };

  configureSabnzbd = ''
    echo "Saving SABnzbd connection..."
    PAYLOAD=$(${pkgs.jq}/bin/jq -n \
      ${sabJq.flagsString} \
      --arg url ${escapeShellArg sabCfg.url} \
      --arg category ${escapeShellArg sabCfg.category} \
      '{ integrations: { sabnzbd: { enabled: true, url: $url, apiKey: ${sabJq.refs.sabnzbdApiKey}, category: $category } } }')
    check_response "save SABnzbd connection" "$(${apiCall "POST" "/settings" "$PAYLOAD"})"
  '';

  disableSabnzbd = ''
    echo "Disabling SABnzbd integration..."
    check_response "disable SABnzbd" "$(${
      apiCall "POST" "/settings" ''{"integrations":{"sabnzbd":{"enabled":false}}}''
    })"
  '';

  sabEnabled = sabCfg.enable && sabnzbd.enable;
  sabDeps =
    optional sabEnabled "sabnzbd.service"
    ++ optional (sabEnabled && sabnzbd.settings.categories != [ ]) "sabnzbd-categories.service";
in
{
  config = mkIf (nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = sabCfg.enable -> sabCfg.apiKey != null;
        message = "`nixflix.aurral.settings.sabnzbd.apiKey` must be set when Aurral's SABnzbd integration is enabled.";
      }
    ];

    systemd.services.aurral-sabnzbd = {
      description = "Configure Aurral's SABnzbd integration";
      after = [ "aurral-setup.service" ] ++ sabDeps;
      requires = [ "aurral-setup.service" ] ++ sabDeps;
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -euo pipefail

        ${apiUtil.preamble}

        ${
          if sabCfg.enable && nixflix.usenetClients.sabnzbd.enable then configureSabnzbd else disableSabnzbd
        }
      '';
    };
  };
}

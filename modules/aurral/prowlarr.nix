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
  prowlarrCfg = cfg.settings.prowlarr;

  apiUtil = import ./apiUtil.nix { inherit lib pkgs cfg; };
  inherit (apiUtil) apiCall;

  prowlarrJq = secrets.mkJqSecretArgs { prowlarrApiKey = prowlarrCfg.apiKey; };

  configureProwlarr = ''
    echo "Saving Prowlarr connection..."
    PAYLOAD=$(${pkgs.jq}/bin/jq -n \
      ${prowlarrJq.flagsString} \
      --arg url ${escapeShellArg prowlarrCfg.url} \
      --argjson categories ${escapeShellArg (builtins.toJSON prowlarrCfg.categories)} \
      '{ integrations: { prowlarr: { enabled: true, url: $url, apiKey: ${prowlarrJq.refs.prowlarrApiKey}, categories: $categories } } }')
    check_response "save Prowlarr connection" "$(${apiCall "POST" "/settings" "$PAYLOAD"})"
  '';

  disableProwlarr = ''
    echo "Disabling Prowlarr integration..."
    check_response "disable Prowlarr" "$(${
      apiCall "POST" "/settings" ''{"integrations":{"prowlarr":{"enabled":false}}}''
    })"
  '';

  prowlarrDeps = optional (prowlarrCfg.enable && nixflix.prowlarr.enable) "prowlarr-config.service";
in
{
  config = mkIf (nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = prowlarrCfg.enable -> prowlarrCfg.apiKey != null;
        message = "`nixflix.aurral.settings.prowlarr.apiKey` must be set when Aurral's Prowlarr integration is enabled.";
      }
    ];

    systemd.services.aurral-prowlarr = {
      description = "Configure Aurral's Prowlarr integration";
      after = [ "aurral-setup.service" ] ++ prowlarrDeps;
      requires = [ "aurral-setup.service" ] ++ prowlarrDeps;
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -euo pipefail

        ${apiUtil.preamble}

        ${if prowlarrCfg.enable && nixflix.prowlarr.enable then configureProwlarr else disableProwlarr}
      '';
    };
  };
}

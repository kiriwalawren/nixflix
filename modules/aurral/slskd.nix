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
  slskdCfg = cfg.settings.slskd;

  apiUtil = import ./apiUtil.nix { inherit lib pkgs cfg; };
  inherit (apiUtil) apiCall;

  slskdJq = secrets.mkJqSecretArgs { slskdApiKey = slskdCfg.apiKey; };

  configureSlskd = ''
    echo "Saving slskd connection..."
    PAYLOAD=$(${pkgs.jq}/bin/jq -n \
      ${slskdJq.flagsString} \
      --arg url ${escapeShellArg slskdCfg.url} \
      '{ integrations: { slskd: { enabled: true, url: $url, apiKey: ${slskdJq.refs.slskdApiKey} } } }')
    check_response "save slskd connection" "$(${apiCall "POST" "/settings" "$PAYLOAD"})"
  '';

  disableSlskd = ''
    echo "Disabling slskd integration..."
    check_response "disable slskd" "$(${
      apiCall "POST" "/settings" ''{"integrations":{"slskd":{"enabled":false}}}''
    })"
  '';

  slskdDeps = optional (slskdCfg.enable && nixflix.slskd.enable) "slskd.service";
in
{
  config = mkIf (nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = slskdCfg.enable -> slskdCfg.apiKey != null;
        message = "`nixflix.aurral.settings.slskd.apiKey` must be set when Aurral's slskd integration is enabled (it defaults to `nixflix.slskd.apiKey`).";
      }
    ];

    systemd.services.aurral-slskd = {
      description = "Configure Aurral's slskd integration";
      after = [ "aurral-setup.service" ] ++ slskdDeps;
      requires = [ "aurral-setup.service" ] ++ slskdDeps;
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -euo pipefail

        ${apiUtil.preamble}

        ${if slskdCfg.enable && nixflix.slskd.enable then configureSlskd else disableSlskd}
      '';
    };
  };
}

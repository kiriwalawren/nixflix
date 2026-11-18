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
  lfmCfg = cfg.settings.lastfm;

  apiUtil = import ./apiUtil.nix { inherit lib pkgs cfg; };
  inherit (apiUtil) apiCall;

  lastfmJq = secrets.mkJqSecretArgs {
    lastfmApiKey = lfmCfg.apiKey;
    lastfmApiSecret = lfmCfg.apiSecret;
  };

  configureLastfm = ''
    echo "Saving Last.fm credentials..."
    PAYLOAD=$(${pkgs.jq}/bin/jq -n \
      ${lastfmJq.flagsString} \
      '{ integrations: { lastfm: { apiKey: ${lastfmJq.refs.lastfmApiKey}, apiSecret: ${lastfmJq.refs.lastfmApiSecret} } } }')
    check_response "save Last.fm credentials" "$(${apiCall "POST" "/settings" "$PAYLOAD"})"
  '';

  clearLastfm = ''
    echo "Clearing Last.fm credentials..."
    check_response "clear Last.fm" "$(${
      apiCall "POST" "/settings" ''{"integrations":{"lastfm":{"apiKey":"","apiSecret":""}}}''
    })"
  '';
in
{
  config = mkIf (nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = lfmCfg.apiSecret != null -> lfmCfg.apiKey != null;
        message = "`nixflix.aurral.settings.lastfm.apiSecret` requires `nixflix.aurral.settings.lastfm.apiKey`.";
      }
    ];

    systemd.services.aurral-lastfm = {
      description = "Configure Aurral's Last.fm credentials";
      after = [ "aurral-setup.service" ];
      requires = [ "aurral-setup.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -euo pipefail

        ${apiUtil.preamble}

        ${if lfmCfg.apiKey != null then configureLastfm else clearLastfm}
      '';
    };
  };
}

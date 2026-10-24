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
  inherit (cfg) liveTv;

  util = import ../util.nix { inherit lib; };
  secrets = import ../../../lib/secrets { inherit lib; };
  authUtil = import ../authUtil.nix { inherit lib pkgs cfg; };
  waitForApiScript = import ../waitForApiScript.nix {
    inherit pkgs;
    jellyfinCfg = cfg;
  };

  baseUrl =
    if cfg.network.baseUrl == "" then
      "http://${cfg.connectionAddress}:${toString cfg.network.internalHttpPort}"
    else
      "http://${cfg.connectionAddress}:${toString cfg.network.internalHttpPort}/${cfg.network.baseUrl}";

  # A secret goes in as the path of the file holding it, never its value.
  valueOrFile =
    key: value:
    if secrets.isSecretRef value then
      { "${key}File" = toString value._secret; }
    else
      { ${key} = value; };

  spec = pkgs.writeText "jellyfin-livetv.json" (
    builtins.toJSON {
      tuners = mapAttrsToList (
        name: t:
        {
          inherit name;
          inherit (t) friendlyName;
          settings = util.recursiveTransform t.settings;
        }
        // valueOrFile "url" t.url
      ) liveTv.tuners;
      providers = mapAttrsToList (
        name: p:
        {
          inherit name;
          inherit (p) tuners;
          settings = util.recursiveTransform p.settings;
        }
        // valueOrFile "path" p.path
      ) liveTv.listingProviders;
    }
  );

  stateFile = "${cfg.dataDir}/nixflix-managed-livetv.json";
  declared = liveTv.tuners != { } || liveTv.listingProviders != { };

  reconcile = pkgs.writeShellApplication {
    name = "jellyfin-livetv-reconcile";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      jq
    ];
    text = builtins.readFile ./reconcile.sh;
  };
in
{
  imports = [ ./options.nix ];

  config = mkIf (nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = all (p: p.tuners == null || all (t: liveTv.tuners ? ${t}) p.tuners) (
          attrValues liveTv.listingProviders
        );
        message = "nixflix.jellyfin.liveTv.listingProviders.<name>.tuners must name tuners declared in nixflix.jellyfin.liveTv.tuners";
      }
    ];

    systemd.services.jellyfin-livetv = {
      description = "Configure Jellyfin Live TV tuners and guides via API";
      after = [ "jellyfin-plugins.service" ] ++ config.nixflix.serviceDependencies;
      requires = [ "jellyfin-plugins.service" ] ++ config.nixflix.serviceDependencies;
      wantedBy = [ "multi-user.target" ];

      # With nothing declared, run only to remove what was declared before.
      unitConfig.ConditionPathExists = mkIf (!declared) stateFile;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = 300;
        ExecStartPre = waitForApiScript;
      };

      script = ''
        set -eu
        source ${authUtil.authScript}
        BASE_URL="${baseUrl}" TOKEN_FILE="${authUtil.token._secret}" \
          ${getExe reconcile} ${spec} ${escapeShellArg stateFile}
      '';
    };
  };
}

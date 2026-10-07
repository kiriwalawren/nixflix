{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config) nixflix;
  cfg = nixflix.navidrome;
  secrets = import ../../../lib/secrets { inherit lib; };
  ndAuth = import ../ndAuth.nix { inherit lib pkgs cfg; };

  enabledPlugins = lib.filterAttrs (_: p: p.enable) cfg.plugins;

  pluginData = lib.mapAttrs (
    pluginName: pluginCfg:
    let
      plainConfigFile = pkgs.writeText "navidrome-plugin-config-${pluginName}.json" (
        builtins.toJSON (secrets.stripSecretRefs pluginCfg.config)
      );
      jqConfigSecrets = secrets.mkNestedJqSecretArgs pluginCfg.config;
    in
    {
      inherit (pluginCfg) apiId allLibraries allowWriteAccess;
      inherit plainConfigFile jqConfigSecrets;
      librariesJson = builtins.toJSON pluginCfg.libraries;
    }
  ) enabledPlugins;
in
{
  config = lib.mkIf (nixflix.enable && cfg.enable && enabledPlugins != { }) {
    systemd.services.navidrome-plugins-config = {
      description = "Configure Navidrome plugins via API";
      after = [ "navidrome-create-admin.service" ];
      requires = [ "navidrome-create-admin.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -eu
        ${ndAuth.snippet}
        nd_login

        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            pluginName: data:
            let
              secretAssignments = lib.concatStringsSep " | " data.jqConfigSecrets.assignments;
              configFilter =
                if data.jqConfigSecrets.hasSecrets then "$plain | ${secretAssignments}" else "$plain";
            in
            ''
              echo "Configuring plugin: ${pluginName} (api id: ${data.apiId})..."
              DESIRED_PLAIN=$(${pkgs.coreutils}/bin/cat ${data.plainConfigFile})
              CONFIG_OBJECT=$(${pkgs.jq}/bin/jq -n \
                ${data.jqConfigSecrets.flagsString} \
                --argjson plain "$DESIRED_PLAIN" \
                '${configFilter}')

              PUT_BODY=$(${pkgs.jq}/bin/jq -n \
                --arg config "$CONFIG_OBJECT" \
                --arg libraries ${lib.escapeShellArg data.librariesJson} \
                '{
                  config: $config,
                  libraries: $libraries,
                  allLibraries: ${lib.boolToString data.allLibraries},
                  allowWriteAccess: ${lib.boolToString data.allowWriteAccess},
                  enabled: true
                }')

              nd_request PUT "/api/plugin/${data.apiId}" "$PUT_BODY"
              if [ "$ND_HTTP_CODE" -lt 200 ] || [ "$ND_HTTP_CODE" -ge 300 ]; then
                echo "Failed to configure plugin ${pluginName} (HTTP $ND_HTTP_CODE): $ND_BODY" >&2
                exit 1
              fi
              echo "Configured plugin: ${pluginName}"
            ''
          ) pluginData
        )}

        echo "Navidrome plugin configuration completed successfully"
      '';
    };
  };
}

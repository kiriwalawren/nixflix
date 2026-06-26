{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix.maintainerr;
  maintainerrUrl = "http://${cfg.connectionAddress}:${toString cfg.port}";

  sanitizeName = name: builtins.replaceStrings [ " " "-" ] [ "_" "_" ] name;

  mkRuleGroupScript =
    ruleCfg:
    let
      staticPayload = {
        inherit (ruleCfg)
          name
          description
          isActive
          dataType
          useRules
          ruleHandlerCronSchedule
          arrAction
          listExclusions
          forceSeerr
          rules
          ;
        collection = {
          inherit (ruleCfg.collection)
            visibleOnRecommended
            visibleOnHome
            deleteAfterDays
            manualCollection
            manualCollectionName
            keepLogsForMonths
            overlayEnabled
            ;
        };
        # Placeholders replaced at runtime
        libraryId = null;
        radarrSettingsId = null;
        sonarrSettingsId = null;
      };
      staticFile = pkgs.writeText "maintainerr-rule-${sanitizeName ruleCfg.name}-static.json" (
        builtins.toJSON staticPayload
      );
    in
    ''
      echo "Configuring rule group: ${ruleCfg.name}..."

      LIBRARY_ID=$(echo "$LIBRARIES" | ${pkgs.jq}/bin/jq -r \
        --arg title ${escapeShellArg ruleCfg.library} \
        '[.[] | select(.title == $title) | .id] | .[0] // empty')
      if [ -z "$LIBRARY_ID" ]; then
        echo "ERROR: Library '${ruleCfg.library}' not found in Maintainerr." >&2
        exit 1
      fi

      ${
        if ruleCfg.radarrServerName != null then
          ''
            RADARR_ID=$(echo "$RADARR_SERVERS" | ${pkgs.jq}/bin/jq -r \
              --arg name ${escapeShellArg ruleCfg.radarrServerName} \
              '[.[] | select(.serverName == $name) | .id] | .[0] // empty')
            if [ -z "$RADARR_ID" ]; then
              echo "ERROR: Radarr server '${ruleCfg.radarrServerName}' not found in Maintainerr settings." >&2
              exit 1
            fi
          ''
        else
          "RADARR_ID=null"
      }

      ${
        if ruleCfg.sonarrServerName != null then
          ''
            SONARR_ID=$(echo "$SONARR_SERVERS" | ${pkgs.jq}/bin/jq -r \
              --arg name ${escapeShellArg ruleCfg.sonarrServerName} \
              '[.[] | select(.serverName == $name) | .id] | .[0] // empty')
            if [ -z "$SONARR_ID" ]; then
              echo "ERROR: Sonarr server '${ruleCfg.sonarrServerName}' not found in Maintainerr settings." >&2
              exit 1
            fi
          ''
        else
          "SONARR_ID=null"
      }

      EXISTING_ID=$(echo "$CURRENT" | ${pkgs.jq}/bin/jq -r \
        --arg name ${escapeShellArg ruleCfg.name} \
        '[.[] | select(.name == $name) | .id] | .[0] // empty')

      PAYLOAD=$(${pkgs.jq}/bin/jq \
        --arg libraryId "$LIBRARY_ID" \
        --argjson radarrId "$RADARR_ID" \
        --argjson sonarrId "$SONARR_ID" \
        '. + {libraryId: $libraryId, radarrSettingsId: $radarrId, sonarrSettingsId: $sonarrId}' \
        ${staticFile})

      if [ -n "$EXISTING_ID" ]; then
        echo "  Updating rule group (id=$EXISTING_ID)..."
        RESULT=$(${pkgs.curl}/bin/curl -s -X PUT \
          -H "Content-Type: application/json" \
          -d "$(echo "$PAYLOAD" | ${pkgs.jq}/bin/jq --argjson id "$EXISTING_ID" '. + {id: $id}')" \
          "${maintainerrUrl}/api/rules")
        echo "$RESULT" | ${pkgs.jq}/bin/jq -e '.code == 1' > /dev/null
      else
        echo "  Creating rule group..."
        RESULT=$(${pkgs.curl}/bin/curl -s -X POST \
          -H "Content-Type: application/json" \
          -d "$PAYLOAD" \
          "${maintainerrUrl}/api/rules")
        echo "$RESULT" | ${pkgs.jq}/bin/jq -e '.code == 1' > /dev/null
      fi
    '';

  declaredNames = builtins.toJSON (map (r: r.name) cfg.rules);
in
{
  imports = [ ./options.nix ];

  config = mkIf (config.nixflix.enable && cfg.enable) {
    systemd.services.maintainerr-rules = {
      description = "Configure Maintainerr rule groups via API";
      after = [ "maintainerr-settings.service" ];
      requires = [ "maintainerr-settings.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "maintainerr-rules" ''
          set -euo pipefail

          echo "Fetching current Maintainerr state..."
          CURRENT=$(${pkgs.curl}/bin/curl -s "${maintainerrUrl}/api/rules")
          LIBRARIES=$(${pkgs.curl}/bin/curl -s "${maintainerrUrl}/api/media-server/libraries")
          RADARR_SERVERS=$(${pkgs.curl}/bin/curl -s "${maintainerrUrl}/api/settings/radarr")
          SONARR_SERVERS=$(${pkgs.curl}/bin/curl -s "${maintainerrUrl}/api/settings/sonarr")

          ${concatStringsSep "\n" (map mkRuleGroupScript cfg.rules)}

          echo "Removing undeclared rule groups..."
          TO_DELETE=$(echo "$CURRENT" | ${pkgs.jq}/bin/jq -r \
            --argjson declared '${declaredNames}' \
            '.[] | select(.name as $n | ($declared | index($n)) == null) | .id')
          for ID in $TO_DELETE; do
            echo "  Deleting undeclared rule group (id=$ID)..."
            ${pkgs.curl}/bin/curl -s -X DELETE \
              "${maintainerrUrl}/api/rules/$ID" > /dev/null
          done

          echo "Maintainerr rules configured successfully."
        '';
      };
    };
  };
}

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

  mkTemplateScript =
    tmplCfg:
    let
      staticPayload = {
        inherit (tmplCfg)
          name
          description
          mode
          canvasWidth
          canvasHeight
          elements
          ;
      };
      staticFile = pkgs.writeText "maintainerr-template-${sanitizeName tmplCfg.name}-static.json" (
        builtins.toJSON staticPayload
      );
    in
    ''
      echo "Configuring overlay template: ${tmplCfg.name}..."

      EXISTING_ID=$(echo "$NON_PRESETS" | ${pkgs.jq}/bin/jq -r \
        --arg name ${escapeShellArg tmplCfg.name} \
        '[.[] | select(.name == $name) | .id] | .[0] // empty')

      if [ -n "$EXISTING_ID" ]; then
        echo "  Updating template (id=$EXISTING_ID)..."
        RESULT=$(${pkgs.curl}/bin/curl -s -X PUT \
          -H "Content-Type: application/json" \
          -d "$(${pkgs.jq}/bin/jq --argjson id "$EXISTING_ID" '. + {id: $id}' ${staticFile})" \
          "${maintainerrUrl}/api/overlays/templates/$EXISTING_ID")
        TEMPLATE_ID=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -e '.id')
      else
        echo "  Creating template..."
        RESULT=$(${pkgs.curl}/bin/curl -s -X POST \
          -H "Content-Type: application/json" \
          -d @${staticFile} \
          "${maintainerrUrl}/api/overlays/templates")
        TEMPLATE_ID=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -e '.id')
      fi

      ${
        if tmplCfg.isDefault then
          ''
            echo "  Setting template as default..."
            ${pkgs.curl}/bin/curl -s -X POST \
              "${maintainerrUrl}/api/overlays/templates/$TEMPLATE_ID/default" > /dev/null
          ''
        else
          ""
      }
    '';

  declaredNames = builtins.toJSON (map (t: t.name) cfg.overlays.templates);

  countDefaults =
    mode: builtins.length (builtins.filter (t: t.mode == mode && t.isDefault) cfg.overlays.templates);
in
{
  imports = [ ./options.nix ];

  config = mkIf (config.nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = countDefaults "poster" <= 1;
        message = "nixflix.maintainerr.overlays.templates: at most one poster template may have isDefault = true";
      }
      {
        assertion = countDefaults "titlecard" <= 1;
        message = "nixflix.maintainerr.overlays.templates: at most one titlecard template may have isDefault = true";
      }
    ];

    systemd.services.maintainerr-overlay-templates = {
      description = "Configure Maintainerr overlay templates via API";
      after = [ "maintainerr-overlays.service" ];
      requires = [ "maintainerr-overlays.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "maintainerr-overlay-templates" ''
          set -euo pipefail

          echo "Fetching current Maintainerr overlay templates..."
          CURRENT=$(${pkgs.curl}/bin/curl -s "${maintainerrUrl}/api/overlays/templates")
          NON_PRESETS=$(echo "$CURRENT" | ${pkgs.jq}/bin/jq '[.[] | select(.isPreset == false)]')

          ${concatStringsSep "\n" (map mkTemplateScript cfg.overlays.templates)}

          ${
            if countDefaults "poster" == 0 then
              ''
                echo "No poster default declared; setting Classic Pill as default..."
                POSTER_PRESET_ID=$(echo "$CURRENT" | ${pkgs.jq}/bin/jq -r \
                  '[.[] | select(.name == "Classic Pill") | .id] | .[0] // empty')
                if [ -n "$POSTER_PRESET_ID" ]; then
                  ${pkgs.curl}/bin/curl -s -X POST \
                    "${maintainerrUrl}/api/overlays/templates/$POSTER_PRESET_ID/default" > /dev/null
                fi
              ''
            else
              ""
          }

          ${
            if countDefaults "titlecard" == 0 then
              ''
                echo "No titlecard default declared; setting Title Card Pill as default..."
                TITLECARD_PRESET_ID=$(echo "$CURRENT" | ${pkgs.jq}/bin/jq -r \
                  '[.[] | select(.name == "Title Card Pill") | .id] | .[0] // empty')
                if [ -n "$TITLECARD_PRESET_ID" ]; then
                  ${pkgs.curl}/bin/curl -s -X POST \
                    "${maintainerrUrl}/api/overlays/templates/$TITLECARD_PRESET_ID/default" > /dev/null
                fi
              ''
            else
              ""
          }

          echo "Removing undeclared overlay templates..."
          TO_DELETE=$(echo "$NON_PRESETS" | ${pkgs.jq}/bin/jq -r \
            --argjson declared '${declaredNames}' \
            '.[] | select(.name as $n | ($declared | index($n)) == null) | .id')
          for ID in $TO_DELETE; do
            echo "  Deleting undeclared template (id=$ID)..."
            ${pkgs.curl}/bin/curl -s -X DELETE \
              "${maintainerrUrl}/api/overlays/templates/$ID" > /dev/null
          done

          echo "Maintainerr overlay templates configured successfully."
        '';
      };
    };
  };
}

{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkIf mkOption types mkEnableOption;
  cfg = config.nixflix.restish;

  enabledServices = lib.attrValues cfg.services;

  restishWrapper = pkgs.writeShellScriptBin "restish" ''
    set -euo pipefail

    if [ -z "''${HOME:-}" ]; then
      export HOME="/tmp"
    fi

    export RESTISH_CONFIG_DIR="''${XDG_CONFIG_HOME:-$HOME/.config}/restish"
    mkdir -p "$RESTISH_CONFIG_DIR"

    ${lib.optionalString ((lib.length enabledServices) > 0) ''
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: svc: ''
          if [ -f "${svc.apiKeyPath}" ]; then
            export ${lib.toUpper name}_API_KEY=$(cat "${svc.apiKeyPath}")
          else
            echo "Warning: API key file not found: ${svc.apiKeyPath}" >&2
          fi
        '')
        cfg.services)}

      CONFIG_FILE="$RESTISH_CONFIG_DIR/apis.json"
      cat > "$CONFIG_FILE" <<'EOF'
      {
        ${lib.concatStringsSep ",\n  " (lib.mapAttrsToList (name: svc: ''
        "${name}": {
          "base": "${svc.baseUrl}",
          "profiles": {
            "default": {
              "headers": {
                "X-Api-Key": "''${${lib.toUpper name}_API_KEY}"
              }
            }
          }
        }'')
      cfg.services)}
      }
      EOF

      TEMP_CONFIG=$(mktemp)
      ${pkgs.envsubst}/bin/envsubst < "$CONFIG_FILE" > "$TEMP_CONFIG"
      mv "$TEMP_CONFIG" "$CONFIG_FILE"
    ''}

    exec ${pkgs.restish}/bin/restish "$@"
  '';
in {
  options.nixflix.restish = {
    services = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          baseUrl = mkOption {
            type = types.str;
            description = "Base URL for the service API";
            example = "http://127.0.0.1:8989/api/v3";
          };

          apiKeyPath = mkOption {
            type = types.path;
            description = "Path to the API key file";
          };
        };
      });
      default = {};
      description = "Services to configure in restish";
    };

    package = mkOption {
      type = types.package;
      default = restishWrapper;
      description = "The restish wrapper package";
      internal = true;
    };
  };

  config = mkIf config.nixflix.enable {
    environment.systemPackages = [restishWrapper];
  };
}

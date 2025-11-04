{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkIf mkOption types mkEnableOption;
  cfg = config.nixflix.restish;

  enabledServices = lib.attrValues cfg.services;

  # Helper to convert header/query names to valid bash variable names
  # Converts to uppercase and replaces hyphens with underscores
  sanitizeVarName = name: lib.replaceStrings ["-"] ["_"] (lib.toUpper name);

  restishWrapper = pkgs.writeShellScriptBin "restish" ''
    set -euo pipefail

    if [ -z "''${HOME:-}" ]; then
      export HOME="/tmp"
    fi

    export RESTISH_CONFIG_DIR="''${XDG_CONFIG_HOME:-$HOME/.config}/restish"
    mkdir -p "$RESTISH_CONFIG_DIR"

    ${lib.optionalString ((lib.length enabledServices) > 0) ''
      # Helper function to read value from file if it exists, otherwise use as-is
      read_value() {
        local value="$1"
        if [ -f "$value" ]; then
          cat "$value"
        else
          echo "$value"
        fi
      }

      # Build JSON config using jq with file locking to prevent concurrent writes
      CONFIG_FILE="$RESTISH_CONFIG_DIR/apis.json"
      LOCK_FILE="$RESTISH_CONFIG_DIR/apis.json.lock"

      # Acquire exclusive lock (will wait if another process has it)
      exec 200>"$LOCK_FILE"
      ${pkgs.util-linux}/bin/flock 200
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: svc: ''
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: ''
              export HEADER_${sanitizeVarName name}_${sanitizeVarName k}=$(read_value "${v}")
            '')
            svc.headers)}
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: ''
              export QUERY_${sanitizeVarName name}_${sanitizeVarName k}=$(read_value "${v}")
            '')
            svc.query)}
        '')
        cfg.services)}

      cat > "$CONFIG_FILE" <<'EOF'
      {
        ${lib.concatStringsSep ",\n" (lib.mapAttrsToList (name: svc: let
        headerPairs = lib.mapAttrsToList (k: v: ''"${k}": "$HEADER_${sanitizeVarName name}_${sanitizeVarName k}"'') svc.headers;
        queryPairs = lib.mapAttrsToList (k: v: ''"${k}": "$QUERY_${sanitizeVarName name}_${sanitizeVarName k}"'') svc.query;
        profileParts =
          (lib.optionals (svc.headers != {}) [''"headers": { ${lib.concatStringsSep ", " headerPairs} }''])
          ++ (lib.optionals (svc.query != {}) [''"query": { ${lib.concatStringsSep ", " queryPairs} }'']);
      in ''
          "${name}": {
            "base": "${svc.baseUrl}",
            "profiles": {
              "default": {
        ${lib.concatStringsSep ",\n" profileParts}
              }
            }
          }'')
      cfg.services)}
      }
      EOF

      # Substitute environment variables
      TEMP_CONFIG=$(mktemp)
      ${pkgs.envsubst}/bin/envsubst < "$CONFIG_FILE" > "$TEMP_CONFIG"
      mv "$TEMP_CONFIG" "$CONFIG_FILE"

      # Release lock
      exec 200>&-
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

          headers = mkOption {
            type = types.attrsOf types.str;
            default = {};
            description = ''
              HTTP headers to send with requests.
              Values can be either plain strings or file paths.
              If a value is a valid file path, it will be read at runtime.
            '';
            example = {
              "X-Api-Key" = "/run/secrets/sonarr/api_key";
              "User-Agent" = "nixflix";
            };
          };

          query = mkOption {
            type = types.attrsOf types.str;
            default = {};
            description = ''
              Query parameters to include in requests.
              Values can be either plain strings or file paths.
              If a value is a valid file path, it will be read at runtime.
            '';
            example = {
              "apikey" = "/run/secrets/sabnzbd/api_key";
              "output" = "json";
            };
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

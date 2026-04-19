{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix.prowlarr;
  secrets = import ../../lib/secrets { inherit lib; };

  mkSecureCurl = import ../../lib/mk-secure-curl.nix { inherit lib pkgs; };
in
{
  options.nixflix.prowlarr.config.indexerProxies = mkOption {
    type = types.listOf (
      types.submodule {
        freeformType = types.attrsOf types.anything;
        options = {
          name = mkOption {
            type = types.str;
            description = "Name of the Prowlarr indexer proxy Schema";
          };
          username = secrets.mkSecretOption {
            description = "Username for the indexer proxy.";
            nullable = true;
          };
          password = secrets.mkSecretOption {
            description = "Password for the indexer proxy.";
            nullable = true;
          };
          tags = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Applies to indexers with at least one matching tag";
          };
        };
      }
    );
    default = [ ];
    description = ''
      List of indexer proxies to configure in Prowlarr.

      Any additional attributes beyond name, username, and password
      will be applied as field values to the indexer schema.

      FlareSolverr is automatically configured with a `flaresolverr` tag when `nixflix.flaresolverr.enable` is `true`;

      You can run the following command to get the field names for a particular indexer:

      ```sh
      curl -s -H "X-Api-Key: $(sudo cat </path/to/prowlarr/apiKey>)" "http://127.0.0.1:9696/prowlarr/api/v1/indexerProxy/schema" | jq '.[] | select(.name=="<indexerName>") | .fields'
      ```

      Or if you have nginx disabled or `config.nixflix.prowlarr.config.hostConfig.urlBase` is not configured

      ```sh
      curl -s -H "X-Api-Key: $(sudo cat </path/to/prowlarr/apiKey>)" "http://127.0.0.1:9696/api/v1/indexerProxy/schema" | jq '.[] | select(.name=="<indexerName>") | .fields'
      ```
    '';
  };

  config.nixflix.prowlarr.config.indexerProxies =
    optional (config.nixflix.enable && cfg.enable && config.nixflix.flaresolverr.enable)
      {
        name = "FlareSolverr";
        host = "http://127.0.0.1:${toString config.nixflix.flaresolverr.port}";
        tags = [ "flaresolverr" ];
      };

  config.systemd.services."prowlarr-indexer-proxies" =
    mkIf (config.nixflix.enable && cfg.enable && cfg.config.apiKey != null)
      {
        description = "Configure Prowlarr indexer proxies via API";
        after = [
          "prowlarr-config.service"
          "prowlarr-tags.service"
        ]
        ++ optional config.nixflix.flaresolverr.enable "flaresolverr.service";
        requires = [
          "prowlarr-config.service"
          "prowlarr-tags.service"
        ]
        ++ optional config.nixflix.flaresolverr.enable "flaresolverr.service";
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          set -eu

          BASE_URL="http://${cfg.config.hostConfig.bindAddress}:${builtins.toString cfg.config.hostConfig.port}${cfg.config.hostConfig.urlBase}/api/${cfg.config.apiVersion}"

          # Fetch all indexer schemas
          echo "Fetching indexer proxy schemas..."
          SCHEMAS=$(${
            mkSecureCurl cfg.config.apiKey {
              url = "$BASE_URL/indexerProxy/schema";
              extraArgs = "-S";
            }
          })

          # Fetch existing indexers
          echo "Fetching existing indexer proxies..."
          INDEXERS=$(${
            mkSecureCurl cfg.config.apiKey {
              url = "$BASE_URL/indexerProxy";
              extraArgs = "-S";
            }
          })

          # Fetch all tags for name-to-ID resolution
          echo "Fetching tags..."
          ALL_TAGS=$(${
            mkSecureCurl cfg.config.apiKey {
              url = "$BASE_URL/tag";
              extraArgs = "-S";
            }
          })

          # Build list of configured indexer proxy names
          CONFIGURED_NAMES=$(cat <<'EOF'
          ${builtins.toJSON (map (i: i.name) cfg.config.indexerProxies)}
          EOF
          )

          # Delete indexers that are not in the configuration
          echo "Removing indexer proxies not in configuration..."
          echo "$INDEXERS" | ${pkgs.jq}/bin/jq -r '.[] | @json' | while IFS= read -r indexer; do
            INDEXER_NAME=$(echo "$indexer" | ${pkgs.jq}/bin/jq -r '.name')
            INDEXER_ID=$(echo "$indexer" | ${pkgs.jq}/bin/jq -r '.id')

            if ! echo "$CONFIGURED_NAMES" | ${pkgs.jq}/bin/jq -e --arg name "$INDEXER_NAME" 'index($name)' >/dev/null 2>&1; then
              echo "Deleting indexer proxy not in config: $INDEXER_NAME (ID: $INDEXER_ID)"
              ${
                mkSecureCurl cfg.config.apiKey {
                  url = "$BASE_URL/indexerProxy/$INDEXER_ID";
                  method = "DELETE";
                  extraArgs = "-Sf";
                }
              } >/dev/null || echo "Warning: Failed to delete indexer proxy $INDEXER_NAME"
            fi
          done

          ${concatMapStringsSep "\n" (
            indexerConfig:
            let
              indexerName = indexerConfig.name;
              inherit (indexerConfig) username password;
              allOverrides = builtins.removeAttrs indexerConfig [
                "username"
                "password"
                "tags"
              ];
              fieldOverrides = lib.filterAttrs (
                name: value: value != null && !lib.hasPrefix "_" name
              ) allOverrides;
              fieldOverridesJson = builtins.toJSON fieldOverrides;

              jqSecrets = secrets.mkJqSecretArgs {
                username = if username == null then "" else username;
                password = if password == null then "" else password;
              };
            in
            ''
              echo "Processing indexer proxy: ${indexerName}"

              apply_field_overrides() {
                local indexer_json="$1"
                local overrides="$2"

                echo "$indexer_json" | ${pkgs.jq}/bin/jq \
                  ${jqSecrets.flagsString} \
                  --argjson overrides "$overrides" '
                    .fields[] |= (
                      if .name == "username" and ${jqSecrets.refs.username} != "" then .value = ${jqSecrets.refs.username}
                      elif .name == "password" and ${jqSecrets.refs.password} != "" then .value = ${jqSecrets.refs.password}
                      else .
                      end
                    )
                    | . + $overrides
                    | .fields[] |= (
                        . as $field |
                        if $overrides[$field.name] != null then
                          .value = $overrides[$field.name]
                        else
                          .
                        end
                      )
                  '
              }

              FIELD_OVERRIDES=${escapeShellArg fieldOverridesJson}

              EXISTING_INDEXER=$(echo "$INDEXERS" | ${pkgs.jq}/bin/jq -r --arg name ${escapeShellArg indexerName} '.[] | select(.name == $name) | @json' || echo "")

              if [ -n "$EXISTING_INDEXER" ]; then
                echo "Indexer proxy ${indexerName} already exists, updating..."
                INDEXER_ID=$(echo "$EXISTING_INDEXER" | ${pkgs.jq}/bin/jq -r '.id')

                UPDATED_INDEXER=$(apply_field_overrides "$EXISTING_INDEXER" "$FIELD_OVERRIDES")

                TAG_IDS=$(echo "$ALL_TAGS" | ${pkgs.jq}/bin/jq --argjson names ${escapeShellArg (builtins.toJSON indexerConfig.tags)} \
                  '[.[] | select(.label as $l | $names | index($l)) | .id]')
                UPDATED_INDEXER=$(echo "$UPDATED_INDEXER" | ${pkgs.jq}/bin/jq --argjson tags "$TAG_IDS" '.tags = $tags')

                ${
                  mkSecureCurl cfg.config.apiKey {
                    url = "$BASE_URL/indexerProxy/$INDEXER_ID";
                    method = "PUT";
                    headers = {
                      "Content-Type" = "application/json";
                    };
                    data = "$UPDATED_INDEXER";
                    extraArgs = "-Sf";
                  }
                } >/dev/null

                echo "Indexer proxy ${indexerName} updated"
              else
                echo "Indexer proxy ${indexerName} does not exist, creating..."

                SCHEMA=$(echo "$SCHEMAS" | ${pkgs.jq}/bin/jq -r --arg name ${escapeShellArg indexerName} '.[] | select(.implementationName == $name) | @json' || echo "")

                if [ -z "$SCHEMA" ]; then
                  echo "Error: No schema found for indexer proxy ${indexerName}"
                  exit 1
                fi

                NEW_INDEXER=$(apply_field_overrides "$SCHEMA" "$FIELD_OVERRIDES")

                TAG_IDS=$(echo "$ALL_TAGS" | ${pkgs.jq}/bin/jq --argjson names ${escapeShellArg (builtins.toJSON indexerConfig.tags)} \
                  '[.[] | select(.label as $l | $names | index($l)) | .id]')
                NEW_INDEXER=$(echo "$NEW_INDEXER" | ${pkgs.jq}/bin/jq --argjson tags "$TAG_IDS" '.tags = $tags')

                ${
                  mkSecureCurl cfg.config.apiKey {
                    url = "$BASE_URL/indexerProxy";
                    method = "POST";
                    headers = {
                      "Content-Type" = "application/json";
                    };
                    data = "$NEW_INDEXER";
                    extraArgs = "-Sf";
                  }
                } >/dev/null

                echo "Indexer proxy ${indexerName} created"
              fi
            ''
          ) cfg.config.indexerProxies}

          echo "Prowlarr indexer proxies configuration complete"
        '';
      };
}

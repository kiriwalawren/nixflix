{
  lib,
  pkgs,
}:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };

  mkSecureCurl = import ../../lib/mk-secure-curl.nix { inherit lib pkgs; };
in
{
  type = mkOption {
    type = types.listOf (
      types.submodule {
        freeformType = types.attrsOf types.anything;
        options = {
          name = mkOption {
            type = types.str;
            description = "Name of the Prowlarr Indexer Schema";
          };
          apiKey = secrets.mkSecretOption {
            description = "API key for the indexer.";
            nullable = true;
          };
          username = secrets.mkSecretOption {
            description = "Username for the indexer.";
            nullable = true;
          };
          password = secrets.mkSecretOption {
            description = "Password for the indexer.";
            nullable = true;
          };
          appProfileId = mkOption {
            type = types.int;
            default = 1;
            description = "Application profile ID for the indexer (default: 1)";
          };
        };
      }
    );
    default = [ ];
    description = ''
      List of indexers to configure in Prowlarr. Prowlarr supports many indexers in addition to any indexer that uses the Newznab/Torznab standard using 'Generic Newznab' (for usenet) or 'Generic Torznab' (for torrents).

      Any additional attributes beyond name, apiKey, username, password, and appProfileId
      will be applied as field values to the indexer schema.

      You can run the following command to get the field names for a particular indexer:

      ```sh
      curl -s -H "X-Api-Key: $(sudo cat </path/to/prowlarr/apiKey>)" "http://127.0.0.1:9696/prowlarr/api/v1/indexer/schema" | jq '.[] | select(.name=="<indexerName>") | .fields'
      ```

      Or if you have nginx disabled or `config.nixflix.prowlarr.config.hostConfig.urlBase` is not configured

      ```sh
      curl -s -H "X-Api-Key: $(sudo cat </path/to/prowlarr/apiKey>)" "http://127.0.0.1:9696/api/v1/indexer/schema" | jq '.[] | select(.name=="<indexerName>") | .fields'
      ```
    '';
  };

  mkService = serviceConfig: {
    description = "Configure Prowlarr indexers via API";
    after = [ "prowlarr-config.service" ];
    requires = [ "prowlarr-config.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      set -eu

      BASE_URL="http://127.0.0.1:${builtins.toString serviceConfig.hostConfig.port}${serviceConfig.hostConfig.urlBase}/api/${serviceConfig.apiVersion}"

      # Fetch all indexer schemas
      echo "Fetching indexer schemas..."
      SCHEMAS=$(${
        mkSecureCurl serviceConfig.apiKey {
          url = "$BASE_URL/indexer/schema";
          extraArgs = "-S";
        }
      })

      # Fetch existing indexers
      echo "Fetching existing indexers..."
      INDEXERS=$(${
        mkSecureCurl serviceConfig.apiKey {
          url = "$BASE_URL/indexer";
          extraArgs = "-S";
        }
      })

      # Build list of configured indexer names
      CONFIGURED_NAMES=$(cat <<'EOF'
      ${builtins.toJSON (map (i: i.name) serviceConfig.indexers)}
      EOF
      )

      # Delete indexers that are not in the configuration
      echo "Removing indexers not in configuration..."
      echo "$INDEXERS" | ${pkgs.jq}/bin/jq -r '.[] | @json' | while IFS= read -r indexer; do
        INDEXER_NAME=$(echo "$indexer" | ${pkgs.jq}/bin/jq -r '.name')
        INDEXER_ID=$(echo "$indexer" | ${pkgs.jq}/bin/jq -r '.id')

        if ! echo "$CONFIGURED_NAMES" | ${pkgs.jq}/bin/jq -e --arg name "$INDEXER_NAME" 'index($name)' >/dev/null 2>&1; then
          echo "Deleting indexer not in config: $INDEXER_NAME (ID: $INDEXER_ID)"
          ${
            mkSecureCurl serviceConfig.apiKey {
              url = "$BASE_URL/indexer/$INDEXER_ID";
              method = "DELETE";
              extraArgs = "-Sf";
            }
          } >/dev/null || echo "Warning: Failed to delete indexer $INDEXER_NAME"
        fi
      done

      ${concatMapStringsSep "\n" (
        indexerConfig:
        let
          indexerName = indexerConfig.name;
          inherit (indexerConfig) apiKey username password;
          allOverrides = builtins.removeAttrs indexerConfig [
            "name"
            "apiKey"
            "username"
            "password"
          ];
          fieldOverrides = lib.filterAttrs (
            name: value: value != null && !lib.hasPrefix "_" name
          ) allOverrides;
          fieldOverridesJson = builtins.toJSON fieldOverrides;

          jqSecrets = secrets.mkJqSecretArgs {
            apiKey = if apiKey == null then "" else apiKey;
            username = if username == null then "" else username;
            password = if password == null then "" else password;
          };
        in
        ''
          echo "Processing indexer: ${indexerName}"

          apply_field_overrides() {
            local indexer_json="$1"
            local overrides="$2"

            echo "$indexer_json" | ${pkgs.jq}/bin/jq \
              ${jqSecrets.flagsString} \
              --argjson overrides "$overrides" '
                .fields[] |= (
                  if .name == "apiKey" and ${jqSecrets.refs.apiKey} != "" then .value = ${jqSecrets.refs.apiKey}
                  elif .name == "username" and ${jqSecrets.refs.username} != "" then .value = ${jqSecrets.refs.username}
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
            echo "Indexer ${indexerName} already exists, updating..."
            INDEXER_ID=$(echo "$EXISTING_INDEXER" | ${pkgs.jq}/bin/jq -r '.id')

            UPDATED_INDEXER=$(apply_field_overrides "$EXISTING_INDEXER" "$FIELD_OVERRIDES")

            ${
              mkSecureCurl serviceConfig.apiKey {
                url = "$BASE_URL/indexer/$INDEXER_ID";
                method = "PUT";
                headers = {
                  "Content-Type" = "application/json";
                };
                data = "$UPDATED_INDEXER";
                extraArgs = "-Sf";
              }
            } >/dev/null

            echo "Indexer ${indexerName} updated"
          else
            echo "Indexer ${indexerName} does not exist, creating..."

            SCHEMA=$(echo "$SCHEMAS" | ${pkgs.jq}/bin/jq -r --arg name ${escapeShellArg indexerName} '.[] | select(.name == $name) | @json' || echo "")

            if [ -z "$SCHEMA" ]; then
              echo "Error: No schema found for indexer ${indexerName}"
              exit 1
            fi

            NEW_INDEXER=$(apply_field_overrides "$SCHEMA" "$FIELD_OVERRIDES")

            ${
              mkSecureCurl serviceConfig.apiKey {
                url = "$BASE_URL/indexer";
                method = "POST";
                headers = {
                  "Content-Type" = "application/json";
                };
                data = "$NEW_INDEXER";
                extraArgs = "-Sf";
              }
            } >/dev/null

            echo "Indexer ${indexerName} created"
          fi
        ''
      ) serviceConfig.indexers}

      echo "Prowlarr indexers configuration complete"
    '';
  };
}

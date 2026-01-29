{
  lib,
  pkgs,
  serviceName,
}:
with lib; let
  secrets = import ../lib/secrets {inherit lib;};
  capitalizedName = lib.toUpper (builtins.substring 0 1 serviceName) + builtins.substring 1 (-1) serviceName;
in {
  type = mkOption {
    type = types.listOf (types.submodule {
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
    });
    default = [];
    description = ''
      List of indexers to configure in Prowlarr.
      Any additional attributes beyond name, apiKey, username, password, and appProfileId
      will be applied as field values to the indexer schema.

      You can run the following command to get the field names for a particular indexer:

      ```sh
      curl -s -H "X-Api-Key: $(sudo cat </path/to/prowlarr/apiKey>)" "http://127.0.0.1:9696/prowlarr/api/v1/indexer/schema" | jq '.[] | select(.implementationName=="<indexerName>") | .fields'
      ```

      Or if you have nginx disabled or `config.nixflix.prowlarr.config.hostConfig.urlBase` is not configured

      ```sh
      curl -s -H "X-Api-Key: $(sudo cat </path/to/prowlarr/apiKey>)" "http://127.0.0.1:9696/api/v1/indexer/schema" | jq '.[] | select(.implementationName=="<indexerName>") | .fields'
      ```
    '';
  };

  mkService = serviceConfig: {
    description = "Configure ${serviceName} indexers via API";
    after = ["${serviceName}-config.service"];
    requires = ["${serviceName}-config.service"];
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      set -eu

      # Read API key secret
      ${secrets.toShellValue "API_KEY" serviceConfig.apiKey}

      BASE_URL="http://127.0.0.1:${builtins.toString serviceConfig.hostConfig.port}${serviceConfig.hostConfig.urlBase}/api/${serviceConfig.apiVersion}"

      # Fetch all indexer schemas
      echo "Fetching indexer schemas..."
      SCHEMAS=$(${pkgs.curl}/bin/curl -sS -H "X-Api-Key: $API_KEY" "$BASE_URL/indexer/schema")

      # Fetch existing indexers
      echo "Fetching existing indexers..."
      INDEXERS=$(${pkgs.curl}/bin/curl -sS -H "X-Api-Key: $API_KEY" "$BASE_URL/indexer")

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
          ${pkgs.curl}/bin/curl -sSf -X DELETE \
            -H "X-Api-Key: $API_KEY" \
            "$BASE_URL/indexer/$INDEXER_ID" >/dev/null || echo "Warning: Failed to delete indexer $INDEXER_NAME"
        fi
      done

      ${concatMapStringsSep "\n" (indexerConfig: let
          indexerName = indexerConfig.name;
          inherit (indexerConfig) apiKey username password;
          allOverrides = builtins.removeAttrs indexerConfig ["name" "apiKey" "username" "password"];
          fieldOverrides = lib.filterAttrs (name: value: value != null && !lib.hasPrefix "_" name) allOverrides;
          fieldOverridesJson = builtins.toJSON fieldOverrides;
        in ''
          echo "Processing indexer: ${indexerName}"

          apply_field_overrides() {
            local indexer_json="$1"
            local api_key="$2"
            local username="$3"
            local password="$4"
            local overrides="$5"

            echo "$indexer_json" | ${pkgs.jq}/bin/jq \
              --arg apiKey "$api_key" \
              --arg username "$username" \
              --arg password "$password" \
              --argjson overrides "$overrides" '
                .fields[] |= (
                  if .name == "apiKey" and $apiKey != "" then .value = $apiKey
                  elif .name == "username" and $username != "" then .value = $username
                  elif .name == "password" and $password != "" then .value = $password
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

          ${
            if apiKey == null
            then "INDEXER_API_KEY=''"
            else secrets.toShellValue "INDEXER_API_KEY" apiKey
          }
          ${
            if username == null
            then "INDEXER_USERNAME=''"
            else secrets.toShellValue "INDEXER_USERNAME" username
          }
          ${
            if password == null
            then "INDEXER_PASSWORD=''"
            else secrets.toShellValue "INDEXER_PASSWORD" password
          }
          FIELD_OVERRIDES='${fieldOverridesJson}'

          EXISTING_INDEXER=$(echo "$INDEXERS" | ${pkgs.jq}/bin/jq -r '.[] | select(.name == "${indexerName}") | @json' || echo "")

          TEMP_FILE=$(mktemp)
          if [ -n "$EXISTING_INDEXER" ]; then
            echo "Indexer ${indexerName} already exists, updating..."
            INDEXER_ID=$(echo "$EXISTING_INDEXER" | ${pkgs.jq}/bin/jq -r '.id')

            UPDATED_INDEXER=$(apply_field_overrides "$EXISTING_INDEXER" "$INDEXER_API_KEY" "$INDEXER_USERNAME" "$INDEXER_PASSWORD" "$FIELD_OVERRIDES")
            echo "$UPDATED_INDEXER" > "$TEMP_FILE"

            ${pkgs.curl}/bin/curl -sSf -X PUT \
              -H "X-Api-Key: $API_KEY" \
              -H "Content-Type: application/json" \
              --data @"$TEMP_FILE" \
              "$BASE_URL/indexer/$INDEXER_ID" >/dev/null

            echo "Indexer ${indexerName} updated"
          else
            echo "Indexer ${indexerName} does not exist, creating..."

            SCHEMA=$(echo "$SCHEMAS" | ${pkgs.jq}/bin/jq -r '.[] | select(.name == "${indexerName}") | @json' || echo "")

            if [ -z "$SCHEMA" ]; then
              echo "Error: No schema found for indexer ${indexerName}"
              exit 1
            fi

            NEW_INDEXER=$(apply_field_overrides "$SCHEMA" "$INDEXER_API_KEY" "$INDEXER_USERNAME" "$INDEXER_PASSWORD" "$FIELD_OVERRIDES")
            echo "$NEW_INDEXER" > "$TEMP_FILE"

            ${pkgs.curl}/bin/curl -sSf -X POST \
              -H "X-Api-Key: $API_KEY" \
              -H "Content-Type: application/json" \
              --data @"$TEMP_FILE" \
              "$BASE_URL/indexer" >/dev/null

            echo "Indexer ${indexerName} created"
          fi
          rm -f "$TEMP_FILE"
        '')
        serviceConfig.indexers}

      echo "${capitalizedName} indexers configuration complete"
    '';
  };
}

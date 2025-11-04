{
  lib,
  pkgs,
}: serviceName: serviceConfig:
with lib; let
  mkWaitForApiScript = import ../arr-common/mkWaitForApiScript.nix {inherit lib pkgs;};
  capitalizedName = lib.toUpper (builtins.substring 0 1 serviceName) + builtins.substring 1 (-1) serviceName;
in {
  description = "Configure ${serviceName} indexers via API";
  after = ["${serviceName}-config.service"];
  requires = ["${serviceName}-config.service"];
  wantedBy = ["multi-user.target"];

  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    ExecStartPre = mkWaitForApiScript serviceName serviceConfig;
  };

  script = ''
    set -eu

    # Read API key secret
    API_KEY=$(cat ${serviceConfig.apiKeyPath})

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
        inherit (indexerConfig) apiKeyPath;
        allOverrides = builtins.removeAttrs indexerConfig ["name" "apiKeyPath"];
        fieldOverrides = lib.filterAttrs (name: value: value != null && !lib.hasPrefix "_" name) allOverrides;
        fieldOverridesJson = builtins.toJSON fieldOverrides;
      in ''
        echo "Processing indexer: ${indexerName}"

        apply_field_overrides() {
          local indexer_json="$1"
          local api_key="$2"
          local overrides="$3"

          echo "$indexer_json" | ${pkgs.jq}/bin/jq \
            --arg apiKey "$api_key" \
            --argjson overrides "$overrides" '
              .fields[] |= (if .name == "apiKey" then .value = $apiKey else . end)
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

        INDEXER_API_KEY=$(cat ${apiKeyPath})
        FIELD_OVERRIDES='${fieldOverridesJson}'

        EXISTING_INDEXER=$(echo "$INDEXERS" | ${pkgs.jq}/bin/jq -r '.[] | select(.name == "${indexerName}") | @json' || echo "")

        if [ -n "$EXISTING_INDEXER" ]; then
          echo "Indexer ${indexerName} already exists, updating..."
          INDEXER_ID=$(echo "$EXISTING_INDEXER" | ${pkgs.jq}/bin/jq -r '.id')

          UPDATED_INDEXER=$(apply_field_overrides "$EXISTING_INDEXER" "$INDEXER_API_KEY" "$FIELD_OVERRIDES")

          ${pkgs.curl}/bin/curl -sSf -X PUT \
            -H "X-Api-Key: $API_KEY" \
            -H "Content-Type: application/json" \
            -d "$UPDATED_INDEXER" \
            "$BASE_URL/indexer/$INDEXER_ID" >/dev/null

          echo "Indexer ${indexerName} updated"
        else
          echo "Indexer ${indexerName} does not exist, creating..."

          SCHEMA=$(echo "$SCHEMAS" | ${pkgs.jq}/bin/jq -r '.[] | select(.name == "${indexerName}") | @json' || echo "")

          if [ -z "$SCHEMA" ]; then
            echo "Error: No schema found for indexer ${indexerName}"
            exit 1
          fi

          NEW_INDEXER=$(apply_field_overrides "$SCHEMA" "$INDEXER_API_KEY" "$FIELD_OVERRIDES")

          ${pkgs.curl}/bin/curl -sSf -X POST \
            -H "X-Api-Key: $API_KEY" \
            -H "Content-Type: application/json" \
            -d "$NEW_INDEXER" \
            "$BASE_URL/indexer" >/dev/null

          echo "Indexer ${indexerName} created"
        fi
      '')
      serviceConfig.indexers}

    echo "${capitalizedName} indexers configuration complete"
  '';
}

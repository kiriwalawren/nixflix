{
  lib,
  pkgs,
  serviceName,
}:
with lib; let
  secrets = import ../lib/secrets {inherit lib;};
  capitalizedName = lib.toUpper (builtins.substring 0 1 serviceName) + builtins.substring 1 (-1) serviceName;

  enumFromAttrs = enum_values:
    types.coercedTo
    (types.enum (lib.attrNames enum_values))
    (name: enum_values.${name})
    (types.enum (lib.attrValues enum_values));
in {
  type = mkOption {
    type = types.listOf (types.submodule {
      options = {
        name = mkOption {
          type = types.str;
          description = "Name of the Prowlarr Indexer Schema";
        };
        apiKey = secrets.mkSecretOption {
          description = "API key for the indexer.";
        };
        appProfileId = mkOption {
          type = types.int;
          default = 1;
          description = "Application profile ID for the indexer (default: 1)";
        };
        "baseSettings.queryLimit" = mkOption {
          type = types.nullOr types.numbers.positive;
          default = null;
          description = "The number of max queries as specified by the respective unit that Prowlarr will allow to the site";
        };
        "baseSettings.grabLimit" = mkOption {
          type = types.nullOr types.numbers.positive;
          default = null;
          description = "The number of max grabs as specified by the respective unit that Prowlarr will allow to the site.";
        };
        "baseSettings.limitsUnit" = mkOption {
          type = enumFromAttrs {
            "Day" = 0;
            "Hour" = 1;
          };
          default = "Day";
          description = "The unit of time for counting limits per indexer.";
        };
        "torrentBaseSettings.appMinimumSeeders" = mkOption {
          type = types.nullOr types.numbers.positive;
          default = null;
          description = "Minimum seeders required by the Applications for the indexer to grab, empty is Sync profile's default.";
        };
        "torrentBaseSettings.preferMagnetUrl" = mkOption {
          type = types.nullOr types.bool;
          default = null;
          description = "When enabled, this indexer will prefer the use of magnet URLs for grabs with fallback to torrent links.";
        };
        "torrentBaseSettings.packSeedTime" = mkOption {
          type = types.nullOr types.numbers.positive;
          default = null;
          description = "The time (in minutes) a pack (season or discography) torrent should be seeded before stopping, empty is app's default.";
        };
        "torrentBaseSettings.seedTime" = mkOption {
          type = types.nullOr types.numbers.positive;
          default = null;
          description = "The time (in minutes) a torrent should be seeded before stopping, empty uses the download client's default.";
        };
        "torrentBaseSettings.seedRatio" = mkOption {
          type = types.nullOr types.numbers.positive;
          default = null;
          description = "The time (in minutes) a torrent should be seeded before stopping, empty uses the download client's default.";
        };
      };
    });
    default = [];
    description = ''
      List of indexers to configure in Prowlarr.
      Any additional attributes beyond what is defined here will be applied as field values to the indexer schema.

      The field names can be kind of hard to figure out. I had to look at the network tab of the developer console.
      In general, the name you see in the UI should be camel case. i.e. "Move first tags to end of release title" becomes `moveFirstTagsToEndOfReleaseTitle`.
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
          inherit (indexerConfig) apiKey;
          allOverrides = builtins.removeAttrs indexerConfig ["name" "apiKey"];
          fieldOverrides = lib.filterAttrs (name: _value: !lib.hasPrefix "_" name) allOverrides;
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
                | . as $indexer
                | ($indexer.fields | map(.name)) as $fieldNames
                | $indexer + ($overrides | to_entries | map(
                    select(.value != null or (($fieldNames | index(.key)) == null))
                  ) | from_entries)
                | .fields[] |= (
                    . as $field |
                    if ($overrides | has($field.name)) then
                      if $overrides[$field.name] != null then
                        .value = $overrides[$field.name]
                      else
                        del(.value)
                      end
                    else
                      .
                    end
                  )
              '
          }

          ${secrets.toShellValue "INDEXER_API_KEY" apiKey}
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
  };
}

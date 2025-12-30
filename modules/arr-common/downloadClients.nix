{
  lib,
  pkgs,
  serviceName,
  config,
}:
with lib; let
  capitalizedName = lib.toUpper (builtins.substring 0 1 serviceName) + builtins.substring 1 (-1) serviceName;
in {
  options = mkOption {
    type = types.listOf (types.submodule {
      freeformType = types.attrsOf types.anything;
      options = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether or not this download client is enabled.";
        };
        name = mkOption {
          type = types.str;
          description = "User-defined name for the download client instance";
        };
        implementationName = mkOption {
          type = types.str;
          description = "Type of download client to configure (matches schema implementationName)";
          example = "SABnzbd";
        };
        apiKeyPath = mkOption {
          type = types.str;
          description = "Path to file containing the API key for the download client";
        };
      };
    });
    default = [];
    defaultText = literalExpression ''
      lib.optionals (nixflix.sabnzbd.enable or false) [
        {
          name = "SABnzbd";
          implementationName = "SABnzbd";
          apiKeyPath = nixflix.sabnzbd.apiKeyPath;
          host = nixflix.sabnzbd.settings.host;
          port = nixflix.sabnzbd.settings.port;
          urlBase = nixflix.sabnzbd.settings.url_base;
        }
      ]
    '';
    description = ''
      List of download clients to configure via the API /downloadclient endpoint.
      Any additional attributes beyond name, implementationName, and apiKeyPath
      will be applied as field values to the download client schema.

      When SABnzbd is enabled, each service is automatically configured with
      the appropriate category field:
      - Radarr uses movieCategory set to "radarr"
      - Sonarr uses tvCategory set to "sonarr"
      - Sonarr Anime uses tvCategory set to "sonarr-anime"
      - Lidarr uses musicCategory set to "lidarr"
      - Prowlarr uses category set to "prowlarr"

      These categories are automatically created in SABnzbd when the
      corresponding service is enabled.
    '';
  };

  mkService = serviceConfig: let
    inherit (lib) optionals;
    inherit (config) nixflix;
  in {
    description = "Configure ${serviceName} download clients via API";
    after = ["${serviceName}-config.service"] ++ optionals (nixflix.sabnzbd.enable or false) ["sabnzbd-config.service"];
    requires = ["${serviceName}-config.service"];
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      set -eu

      # Read API key secret
      API_KEY=$(cat ${serviceConfig.apiKeyPath})

      BASE_URL="http://127.0.0.1:${builtins.toString serviceConfig.hostConfig.port}${serviceConfig.hostConfig.urlBase}/api/${serviceConfig.apiVersion}"

      # Fetch all download client schemas
      echo "Fetching download client schemas..."
      SCHEMAS=$(${pkgs.curl}/bin/curl -sS -H "X-Api-Key: $API_KEY" "$BASE_URL/downloadclient/schema")

      # Fetch existing download clients
      echo "Fetching existing download clients..."
      DOWNLOAD_CLIENTS=$(${pkgs.curl}/bin/curl -sS -H "X-Api-Key: $API_KEY" "$BASE_URL/downloadclient")

      # Build list of configured download client names
      CONFIGURED_NAMES=$(cat <<'EOF'
      ${builtins.toJSON (map (d: d.name) serviceConfig.downloadClients)}
      EOF
      )

      # Delete download clients that are not in the configuration
      echo "Removing download clients not in configuration..."
      echo "$DOWNLOAD_CLIENTS" | ${pkgs.jq}/bin/jq -r '.[] | @json' | while IFS= read -r downloadClient; do
        CLIENT_NAME=$(echo "$downloadClient" | ${pkgs.jq}/bin/jq -r '.name')
        CLIENT_ID=$(echo "$downloadClient" | ${pkgs.jq}/bin/jq -r '.id')

        if ! echo "$CONFIGURED_NAMES" | ${pkgs.jq}/bin/jq -e --arg name "$CLIENT_NAME" 'index($name)' >/dev/null 2>&1; then
          echo "Deleting download client not in config: $CLIENT_NAME (ID: $CLIENT_ID)"
          ${pkgs.curl}/bin/curl -sSf -X DELETE \
            -H "X-Api-Key: $API_KEY" \
            "$BASE_URL/downloadclient/$CLIENT_ID" >/dev/null || echo "Warning: Failed to delete download client $CLIENT_NAME"
        fi
      done

      ${concatMapStringsSep "\n" (clientConfig: let
          clientName = clientConfig.name;
          inherit (clientConfig) implementationName;
          inherit (clientConfig) apiKeyPath;
          allOverrides = builtins.removeAttrs clientConfig ["implementationName" "apiKeyPath"];
          fieldOverrides = lib.filterAttrs (name: value: value != null && !lib.hasPrefix "_" name) allOverrides;
          fieldOverridesJson = builtins.toJSON fieldOverrides;
        in ''
          echo "Processing download client: ${clientName}"

          apply_field_overrides() {
            local client_json="$1"
            local api_key="$2"
            local overrides="$3"

            echo "$client_json" | ${pkgs.jq}/bin/jq \
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

          CLIENT_API_KEY=$(cat ${apiKeyPath})
          FIELD_OVERRIDES='${fieldOverridesJson}'

          EXISTING_CLIENT=$(echo "$DOWNLOAD_CLIENTS" | ${pkgs.jq}/bin/jq -r '.[] | select(.name == "${clientName}") | @json' || echo "")

          if [ -n "$EXISTING_CLIENT" ]; then
            echo "Download client ${clientName} already exists, updating..."
            CLIENT_ID=$(echo "$EXISTING_CLIENT" | ${pkgs.jq}/bin/jq -r '.id')

            UPDATED_CLIENT=$(apply_field_overrides "$EXISTING_CLIENT" "$CLIENT_API_KEY" "$FIELD_OVERRIDES")

            ${pkgs.curl}/bin/curl -sSf -X PUT \
              -H "X-Api-Key: $API_KEY" \
              -H "Content-Type: application/json" \
              -d "$UPDATED_CLIENT" \
              "$BASE_URL/downloadclient/$CLIENT_ID" >/dev/null

            echo "Download client ${clientName} updated"
          else
            echo "Download client ${clientName} does not exist, creating..."

            SCHEMA=$(echo "$SCHEMAS" | ${pkgs.jq}/bin/jq -r '.[] | select(.implementationName == "${implementationName}") | @json' || echo "")

            if [ -z "$SCHEMA" ]; then
              echo "Error: No schema found for download client implementationName ${implementationName}"
              exit 1
            fi

            NEW_CLIENT=$(apply_field_overrides "$SCHEMA" "$CLIENT_API_KEY" "$FIELD_OVERRIDES")

            ${pkgs.curl}/bin/curl -sSf -X POST \
              -H "X-Api-Key: $API_KEY" \
              -H "Content-Type: application/json" \
              -d "$NEW_CLIENT" \
              "$BASE_URL/downloadclient" >/dev/null

            echo "Download client ${clientName} created"
          fi
        '')
        serviceConfig.downloadClients}

      echo "${capitalizedName} download clients configuration complete"
    '';
  };
}

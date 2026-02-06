{
  config,
  lib,
  pkgs,
}:
with lib; let
  secrets = import ../lib/secrets {inherit lib;};
in {
  type = mkOption {
    type = types.listOf (types.submodule {
      freeformType = types.attrsOf types.anything;
      options = {
        name = mkOption {
          type = types.str;
          description = "User-defined name for the application instance";
        };
        implementationName = mkOption {
          type = types.enum ["LazyLibrarian" "Lidarr" "Mylar" "Readarr" "Radarr" "Sonarr" "Whisparr"];
          description = "Type of application to configure (matches schema implementationName)";
        };
        apiKey = secrets.mkSecretOption {
          description = "Path to file containing the API key for the application";
        };
      };
    });
    default = [];
    defaultText = literalExpression ''
      # Automatically configured for enabled arr services (Sonarr, Radarr, Lidarr)
      # Each enabled service gets an application entry with computed baseUrl and prowlarrUrl
      # based on nginx configuration
    '';
    description = ''
      List of applications to configure in Prowlarr.
      Any additional attributes beyond name, implementationName, and apiKey
      will be applied as field values to the application schema.
    '';
  };

  mkService = serviceConfig: {
    description = "Configure Prowlarr applications via API";
    after =
      ["prowlarr-config.service"]
      ++ lib.optional config.nixflix.radarr.enable "radarr-config.service"
      ++ lib.optional config.nixflix.sonarr.enable "sonarr-config.service"
      ++ lib.optional config.nixflix.sonarr-anime.enable "sonarr-anime-config.service"
      ++ lib.optional config.nixflix.lidarr.enable "lidarr-config.service";
    requires =
      ["prowlarr-config.service"]
      ++ lib.optional config.nixflix.radarr.enable "radarr-config.service"
      ++ lib.optional config.nixflix.sonarr.enable "sonarr-config.service"
      ++ lib.optional config.nixflix.sonarr-anime.enable "sonarr-anime-config.service"
      ++ lib.optional config.nixflix.lidarr.enable "lidarr-config.service";
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

      # Fetch all application schemas
      echo "Fetching application schemas..."
      SCHEMAS=$(${pkgs.curl}/bin/curl -sS -H "X-Api-Key: $API_KEY" "$BASE_URL/applications/schema")

      # Fetch existing applications
      echo "Fetching existing applications..."
      APPLICATIONS=$(${pkgs.curl}/bin/curl -sS -H "X-Api-Key: $API_KEY" "$BASE_URL/applications")

      # Build list of configured application names
      CONFIGURED_NAMES=$(cat <<'EOF'
      ${builtins.toJSON (map (a: a.name) serviceConfig.applications)}
      EOF
      )

      # Delete applications that are not in the configuration
      echo "Removing applications not in configuration..."
      echo "$APPLICATIONS" | ${pkgs.jq}/bin/jq -r '.[] | @json' | while IFS= read -r application; do
        APPLICATION_NAME=$(echo "$application" | ${pkgs.jq}/bin/jq -r '.name')
        APPLICATION_ID=$(echo "$application" | ${pkgs.jq}/bin/jq -r '.id')

        if ! echo "$CONFIGURED_NAMES" | ${pkgs.jq}/bin/jq -e --arg name "$APPLICATION_NAME" 'index($name)' >/dev/null; then
          echo "Deleting application not in config: $APPLICATION_NAME (ID: $APPLICATION_ID)"
          ${pkgs.curl}/bin/curl -sSf -X DELETE \
            -H "X-Api-Key: $API_KEY" \
            "$BASE_URL/applications/$APPLICATION_ID" >/dev/null || echo "Warning: Failed to delete application $APPLICATION_NAME"
        fi
      done

      ${concatMapStringsSep "\n" (applicationConfig: let
          applicationName = applicationConfig.name;
          inherit (applicationConfig) implementationName;
          inherit (applicationConfig) apiKey;
          allOverrides = builtins.removeAttrs applicationConfig ["implementationName" "apiKey"];
          fieldOverrides = lib.filterAttrs (name: value: value != null && !lib.hasPrefix "_" name) allOverrides;
          fieldOverridesJson = builtins.toJSON fieldOverrides;
        in ''
          echo "Processing application: ${applicationName}"

          apply_field_overrides() {
            local application_json="$1"
            local api_key="$2"
            local overrides="$3"

            echo "$application_json" | ${pkgs.jq}/bin/jq \
              --arg apiKey "$api_key" \
              --argjson overrides "$overrides" '
                .fields[] |= (if .name == "apiKey" then .value = $apiKey else . end)
                | .name = $overrides.name
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

          ${secrets.toShellValue "APPLICATION_API_KEY" apiKey}
          FIELD_OVERRIDES='${fieldOverridesJson}'

          EXISTING_APPLICATION=$(echo "$APPLICATIONS" | ${pkgs.jq}/bin/jq -r '.[] | select(.name == "${applicationName}") | @json' || echo "")

          if [ -n "$EXISTING_APPLICATION" ]; then
            echo "Application ${applicationName} already exists, updating..."
            APPLICATION_ID=$(echo "$EXISTING_APPLICATION" | ${pkgs.jq}/bin/jq -r '.id')

            UPDATED_APPLICATION=$(apply_field_overrides "$EXISTING_APPLICATION" "$APPLICATION_API_KEY" "$FIELD_OVERRIDES")

            ${pkgs.curl}/bin/curl -sSf -X PUT \
              -H "X-Api-Key: $API_KEY" \
              -H "Content-Type: application/json" \
              -d "$UPDATED_APPLICATION" \
              "$BASE_URL/applications/$APPLICATION_ID" >/dev/null

            echo "Application ${applicationName} updated"
          else
            echo "Application ${applicationName} does not exist, creating..."

            SCHEMA=$(echo "$SCHEMAS" | ${pkgs.jq}/bin/jq -r '.[] | select(.implementationName == "${implementationName}") | @json' || echo "")

            if [ -z "$SCHEMA" ]; then
              echo "Error: No schema found for application implementationName ${implementationName}"
              exit 1
            fi

            NEW_APPLICATION=$(apply_field_overrides "$SCHEMA" "$APPLICATION_API_KEY" "$FIELD_OVERRIDES")

            ${pkgs.curl}/bin/curl -sSf -X POST \
              -H "X-Api-Key: $API_KEY" \
              -H "Content-Type: application/json" \
              -d "$NEW_APPLICATION" \
              "$BASE_URL/applications" >/dev/null

            echo "Application ${applicationName} created"
          fi
        '')
        serviceConfig.applications}

      echo "Prowlarr applications configuration complete"
    '';
  };
}

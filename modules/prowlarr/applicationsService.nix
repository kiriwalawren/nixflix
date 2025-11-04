{
  lib,
  pkgs,
  restishPackage,
}:
# Helper function to create a systemd service that configures Prowlarr applications via API
serviceName: serviceConfig:
with lib; let
  mkWaitForApiScript = import ../arr-common/mkWaitForApiScript.nix {
    inherit lib pkgs restishPackage;
  };
  capitalizedName = lib.toUpper (builtins.substring 0 1 serviceName) + builtins.substring 1 (-1) serviceName;
in {
  description = "Configure ${serviceName} applications via API";
  after = ["${serviceName}-config.service"];
  requires = ["${serviceName}-config.service"];
  wantedBy = ["multi-user.target"];

  path = [restishPackage pkgs.jq];

  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    ExecStartPre = mkWaitForApiScript serviceName serviceConfig;
  };

  script = ''
    set -eu

    # Fetch all application schemas
    echo "Fetching application schemas..."
    SCHEMAS=$(restish -o json ${serviceName}/applications/schema)

    # Fetch existing applications
    echo "Fetching existing applications..."
    APPLICATIONS=$(restish -o json ${serviceName}/applications)

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

      if ! echo "$CONFIGURED_NAMES" | ${pkgs.jq}/bin/jq -e --arg name "$APPLICATION_NAME" 'index($name)' >/dev/null 2>&1; then
        echo "Deleting application not in config: $APPLICATION_NAME (ID: $APPLICATION_ID)"
        restish delete ${serviceName}/applications/$APPLICATION_ID > /dev/null \
          || echo "Warning: Failed to delete application $APPLICATION_NAME"
      fi
    done

    ${concatMapStringsSep "\n" (applicationConfig: let
        applicationName = applicationConfig.name;
        inherit (applicationConfig) implementationName;
        inherit (applicationConfig) apiKeyPath;
        allOverrides = builtins.removeAttrs applicationConfig ["implementationName" "apiKeyPath"];
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

        APPLICATION_API_KEY=$(cat ${apiKeyPath})
        FIELD_OVERRIDES='${fieldOverridesJson}'

        EXISTING_APPLICATION=$(echo "$APPLICATIONS" | ${pkgs.jq}/bin/jq -r '.[] | select(.name == "${applicationName}") | @json' || echo "")

        if [ -n "$EXISTING_APPLICATION" ]; then
          echo "Application ${applicationName} already exists, updating..."
          APPLICATION_ID=$(echo "$EXISTING_APPLICATION" | ${pkgs.jq}/bin/jq -r '.id')

          UPDATED_APPLICATION=$(apply_field_overrides "$EXISTING_APPLICATION" "$APPLICATION_API_KEY" "$FIELD_OVERRIDES")

          echo "$UPDATED_APPLICATION" | restish put ${serviceName}/applications/$APPLICATION_ID > /dev/null

          echo "Application ${applicationName} updated"
        else
          echo "Application ${applicationName} does not exist, creating..."

          SCHEMA=$(echo "$SCHEMAS" | ${pkgs.jq}/bin/jq -r '.[] | select(.implementationName == "${implementationName}") | @json' || echo "")

          if [ -z "$SCHEMA" ]; then
            echo "Error: No schema found for application implementationName ${implementationName}"
            exit 1
          fi

          NEW_APPLICATION=$(apply_field_overrides "$SCHEMA" "$APPLICATION_API_KEY" "$FIELD_OVERRIDES")

          echo "$NEW_APPLICATION" | restish post ${serviceName}/applications > /dev/null

          echo "Application ${applicationName} created"
        fi
      '')
      serviceConfig.applications}

    echo "${capitalizedName} applications configuration complete"
  '';
}

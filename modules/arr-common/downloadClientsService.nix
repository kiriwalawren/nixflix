{
  lib,
  pkgs,
  restishPackage,
}: serviceName: serviceConfig:
with lib; let
  mkWaitForApiScript = import ./mkWaitForApiScript.nix {
    inherit lib pkgs restishPackage;
  };
  capitalizedName = lib.toUpper (builtins.substring 0 1 serviceName) + builtins.substring 1 (-1) serviceName;
in {
  description = "Configure ${serviceName} download clients via API";
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

    # Fetch all download client schemas
    echo "Fetching download client schemas..."
    SCHEMAS=$(restish -o json ${serviceName}/downloadclient/schema)

    # Fetch existing download clients
    echo "Fetching existing download clients..."
    DOWNLOAD_CLIENTS=$(restish -o json ${serviceName}/downloadclient)

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
        restish delete ${serviceName}/downloadclient/$CLIENT_ID > /dev/null \
          || echo "Warning: Failed to delete download client $CLIENT_NAME"
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

          echo "$UPDATED_CLIENT" | restish put ${serviceName}/downloadclient/$CLIENT_ID > /dev/null

          echo "Download client ${clientName} updated"
        else
          echo "Download client ${clientName} does not exist, creating..."

          SCHEMA=$(echo "$SCHEMAS" | ${pkgs.jq}/bin/jq -r '.[] | select(.implementationName == "${implementationName}") | @json' || echo "")

          if [ -z "$SCHEMA" ]; then
            echo "Error: No schema found for download client implementationName ${implementationName}"
            exit 1
          fi

          NEW_CLIENT=$(apply_field_overrides "$SCHEMA" "$CLIENT_API_KEY" "$FIELD_OVERRIDES")

          echo "$NEW_CLIENT" | restish post ${serviceName}/downloadclient > /dev/null

          echo "Download client ${clientName} created"
        fi
      '')
      serviceConfig.downloadClients}

    echo "${capitalizedName} download clients configuration complete"
  '';
}

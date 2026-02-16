{
  lib,
  pkgs,
  serviceName,
  config,
}:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  mkSecureCurl = import ../../lib/mk-secure-curl.nix { inherit lib pkgs; };
  capitalizedName =
    lib.toUpper (builtins.substring 0 1 serviceName) + builtins.substring 1 (-1) serviceName;
in
{
  options = mkOption {
    type = types.listOf (
      types.submodule {
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
          apiKey = secrets.mkSecretOption {
            description = "API key for the download client.";
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
        };
      }
    );
    default = [ ];
    defaultText = literalExpression ''
      lib.optional (nixflix.sabnzbd.enable or false) {
        name = "SABnzbd";
        implementationName = "SABnzbd";
        apiKey = nixflix.sabnzbd.settings.misc.api_key;
        host = nixflix.sabnzbd.settings.host;
        port = nixflix.sabnzbd.settings.port;
        urlBase = nixflix.sabnzbd.settings.url_base;
      }
    '';
    description = ''
      List of download clients to configure via the API /downloadclient endpoint.
      Any additional attributes beyond name, implementationName, apiKey, username, and password
      will be applied as field values to the download client schema.

      A list of `implementationNames` can be acquired with:

      ```sh
      curl -s -H "X-Api-Key: $(sudo cat </path/to/prowlarr/api_key>)" "http://127.0.0.1:9696/prowlarr/api/v1/downloadclient/schema" | jq '.[].implementationName'`
      ```

      You can run the following command to get the field names for a particular `implementationName`:

      ```sh
      curl -s -H "X-Api-Key: $(sudo cat </path/to/prowlarr/apiKey>)" "http://127.0.0.1:9696/prowlarr/api/v1/downloadclient/schema" | jq '.[] | select(.implementationName=="<indexerName>") | .fields'
      ```

      Or if you have nginx disabled or `config.nixflix.prowlarr.config.hostConfig.urlBase` is not configured

      ```sh
      curl -s -H "X-Api-Key: $(sudo cat </path/to/prowlarr/apiKey>)" "http://127.0.0.1:9696/api/v1/indexer/schema" | jq '.[] | select(.implementationName=="<indexerName>") | .fields'
      ```

      ### SABnzbd

      When `nixflix.sabnzbd.enable = true;`, each service is automatically configured with
      the appropriate category field:
      - Radarr uses movieCategory set to "radarr"
      - Sonarr uses tvCategory set to "sonarr"
      - Sonarr Anime uses tvCategory set to "sonarr-anime"
      - Lidarr uses musicCategory set to "lidarr"
      - Prowlarr uses category set to "prowlarr"

      These categories are automatically created in SABnzbd
      during it's setup phase.
    '';
  };

  mkService = serviceConfig: {
    description = "Configure ${serviceName} download clients via API";
    after = [
      "${serviceName}-config.service"
    ]
    ++ lib.optional (config.nixflix.sabnzbd.enable or false) "sabnzbd-categories.service";
    requires = [
      "${serviceName}-config.service"
    ]
    ++ lib.optional (config.nixflix.sabnzbd.enable or false) "sabnzbd-categories.service";
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      set -eu

      BASE_URL="http://127.0.0.1:${builtins.toString serviceConfig.hostConfig.port}${serviceConfig.hostConfig.urlBase}/api/${serviceConfig.apiVersion}"

      # Fetch all download client schemas
      echo "Fetching download client schemas..."
      SCHEMAS=$(${
        mkSecureCurl serviceConfig.apiKey {
          url = "$BASE_URL/downloadclient/schema";
          extraArgs = "-S";
        }
      })

      # Fetch existing download clients
      echo "Fetching existing download clients..."
      DOWNLOAD_CLIENTS=$(${
        mkSecureCurl serviceConfig.apiKey {
          url = "$BASE_URL/downloadclient";
          extraArgs = "-S";
        }
      })

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
          ${
            mkSecureCurl serviceConfig.apiKey {
              url = "$BASE_URL/downloadclient/$CLIENT_ID";
              method = "DELETE";
              extraArgs = "-Sf";
            }
          } >/dev/null || echo "Warning: Failed to delete download client $CLIENT_NAME"
        fi
      done

      ${concatMapStringsSep "\n" (
        clientConfig:
        let
          clientName = clientConfig.name;
          inherit (clientConfig)
            implementationName
            apiKey
            username
            password
            ;
          allOverrides = builtins.removeAttrs clientConfig [
            "implementationName"
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
          echo "Processing download client: ${clientName}"

          apply_field_overrides() {
            local client_json="$1"
            local overrides="$2"

            echo "$client_json" | ${pkgs.jq}/bin/jq \
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

          FIELD_OVERRIDES='${fieldOverridesJson}'

          EXISTING_CLIENT=$(echo "$DOWNLOAD_CLIENTS" | ${pkgs.jq}/bin/jq -r '.[] | select(.name == "${clientName}") | @json' || echo "")

          if [ -n "$EXISTING_CLIENT" ]; then
            echo "Download client ${clientName} already exists, updating..."
            CLIENT_ID=$(echo "$EXISTING_CLIENT" | ${pkgs.jq}/bin/jq -r '.id')

            UPDATED_CLIENT=$(apply_field_overrides "$EXISTING_CLIENT" "$FIELD_OVERRIDES")

            ${
              mkSecureCurl serviceConfig.apiKey {
                url = "$BASE_URL/downloadclient/$CLIENT_ID";
                method = "PUT";
                headers = {
                  "Content-Type" = "application/json";
                };
                data = "$UPDATED_CLIENT";
                extraArgs = "-Sf";
              }
            } >/dev/null

            echo "Download client ${clientName} updated"
          else
            echo "Download client ${clientName} does not exist, creating..."

            SCHEMA=$(echo "$SCHEMAS" | ${pkgs.jq}/bin/jq -r '.[] | select(.implementationName == "${implementationName}") | @json' || echo "")

            if [ -z "$SCHEMA" ]; then
              echo "Error: No schema found for download client implementationName ${implementationName}"
              exit 1
            fi

            NEW_CLIENT=$(apply_field_overrides "$SCHEMA" "$FIELD_OVERRIDES")

            ${
              mkSecureCurl serviceConfig.apiKey {
                url = "$BASE_URL/downloadclient";
                method = "POST";
                headers = {
                  "Content-Type" = "application/json";
                };
                data = "$NEW_CLIENT";
                extraArgs = "-Sf";
              }
            } >/dev/null

            echo "Download client ${clientName} created"
          fi
        ''
      ) serviceConfig.downloadClients}

      echo "${capitalizedName} download clients configuration complete"
    '';
  };
}

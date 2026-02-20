{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  mkSecureCurl = import ../../lib/mk-secure-curl.nix { inherit lib pkgs; };

  cfg = config.nixflix.downloadarr;

  allClients = filter (c: c.enable) (
    builtins.attrValues (
      builtins.removeAttrs cfg [
        "extraClients"
        "enable"
      ]
    )
    ++ cfg.extraClients
  );

  clientDependencies = unique (concatMap (c: c.dependencies) allClients);

  categoryFieldFor =
    serviceName:
    {
      radarr = "movieCategory";
      sonarr = "tvCategory";
      sonarr-anime = "tvCategory";
      lidarr = "musicCategory";
      prowlarr = "category";
    }
    .${serviceName};

  arrServices = [
    "radarr"
    "sonarr"
    "sonarr-anime"
    "lidarr"
    "prowlarr"
  ];

  transformClient =
    serviceName: client:
    let
      stripped = builtins.removeAttrs client [
        "enable"
        "categories"
        "dependencies"
      ];
      categoryField = categoryFieldFor serviceName;
      categoryValue = client.categories.${serviceName};
    in
    stripped // { ${categoryField} = categoryValue; };

  mkDownloadClientsService =
    serviceName:
    let
      serviceConfig = config.nixflix.${serviceName}.config;
      capitalizedName =
        toUpper (builtins.substring 0 1 serviceName) + builtins.substring 1 (-1) serviceName;

      clients = map (transformClient serviceName) allClients;
    in
    {
      "${serviceName}-downloadclients" = {
        description = "Configure ${serviceName} download clients via API";
        after = [ "${serviceName}-config.service" ] ++ clientDependencies;
        requires = [ "${serviceName}-config.service" ] ++ clientDependencies;
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
          ${builtins.toJSON (map (d: d.name) clients)}
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
              inherit (clientConfig) implementationName;
              apiKey = clientConfig.apiKey or null;
              username = clientConfig.username or null;
              password = clientConfig.password or null;
              allOverrides = builtins.removeAttrs clientConfig [
                "implementationName"
                "apiKey"
                "username"
                "password"
              ];
              fieldOverrides = filterAttrs (name: value: value != null && !hasPrefix "_" name) allOverrides;
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

              FIELD_OVERRIDES=${escapeShellArg fieldOverridesJson}

              EXISTING_CLIENT=$(echo "$DOWNLOAD_CLIENTS" | ${pkgs.jq}/bin/jq -r --arg name ${escapeShellArg clientName} '.[] | select(.name == $name) | @json' || echo "")

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

                SCHEMA=$(echo "$SCHEMAS" | ${pkgs.jq}/bin/jq -r --arg implName ${escapeShellArg implementationName} '.[] | select(.implementationName == $implName) | @json' || echo "")

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
          ) clients}

          echo "${capitalizedName} download clients configuration complete"
        '';
      };
    };

  enabledArrServices = filter (
    serviceName:
    config.nixflix.enable
    && allClients != [ ]
    && (config.nixflix.${serviceName}.enable or false)
    && (config.nixflix.${serviceName}.config.apiKey or null) != null
  ) arrServices;
in
{
  config = mkIf (config.nixflix.enable && cfg.enable && allClients != [ ]) {
    systemd.services = mkMerge (map mkDownloadClientsService enabledArrServices);
  };
}

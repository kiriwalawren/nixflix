{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix.prowlarr;
  secrets = import ../../lib/secrets { inherit lib; };
  mkSecureCurl = import ../../lib/mk-secure-curl.nix { inherit lib pkgs; };
in
{
  options.nixflix.prowlarr.config.applications = mkOption {
    type = types.listOf (
      types.submodule {
        freeformType = types.attrsOf types.anything;
        options = {
          name = mkOption {
            type = types.str;
            description = "User-defined name for the application instance";
          };
          implementationName = mkOption {
            type = types.enum [
              "LazyLibrarian"
              "Lidarr"
              "Mylar"
              "Readarr"
              "Radarr"
              "Sonarr"
              "Whisparr"
            ];
            description = "Type of application to configure (matches schema implementationName)";
          };
          apiKey = secrets.mkSecretOption {
            description = "Path to file containing the API key for the application";
          };
        };
      }
    );
    default = [ ];
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

  config.systemd.services."prowlarr-applications" =
    mkIf (config.nixflix.enable && cfg.enable && cfg.config.apiKey != null)
      {
        description = "Configure Prowlarr applications via API";
        after = [
          "prowlarr-config.service"
        ]
        ++ lib.optional config.nixflix.radarr.enable "radarr-config.service"
        ++ lib.optional config.nixflix.sonarr.enable "sonarr-config.service"
        ++ lib.optional config.nixflix.sonarr-anime.enable "sonarr-anime-config.service"
        ++ lib.optional config.nixflix.lidarr.enable "lidarr-config.service";
        requires = [
          "prowlarr-config.service"
        ]
        ++ lib.optional config.nixflix.radarr.enable "radarr-config.service"
        ++ lib.optional config.nixflix.sonarr.enable "sonarr-config.service"
        ++ lib.optional config.nixflix.sonarr-anime.enable "sonarr-anime-config.service"
        ++ lib.optional config.nixflix.lidarr.enable "lidarr-config.service";
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          set -eu

          BASE_URL="http://${cfg.config.hostConfig.bindAddress}:${builtins.toString cfg.config.hostConfig.port}${cfg.config.hostConfig.urlBase}/api/${cfg.config.apiVersion}"

          # Fetch all application schemas
          echo "Fetching application schemas..."
          SCHEMAS=$(${
            mkSecureCurl cfg.config.apiKey {
              url = "$BASE_URL/applications/schema";
              extraArgs = "-S";
            }
          })

          # Fetch existing applications
          echo "Fetching existing applications..."
          APPLICATIONS=$(${
            mkSecureCurl cfg.config.apiKey {
              url = "$BASE_URL/applications";
              extraArgs = "-S";
            }
          })

          # Build list of configured application names
          CONFIGURED_NAMES=$(cat <<'EOF'
          ${builtins.toJSON (map (a: a.name) cfg.config.applications)}
          EOF
          )

          # Delete applications that are not in the configuration
          echo "Removing applications not in configuration..."
          echo "$APPLICATIONS" | ${pkgs.jq}/bin/jq -r '.[] | @json' | while IFS= read -r application; do
            APPLICATION_NAME=$(echo "$application" | ${pkgs.jq}/bin/jq -r '.name')
            APPLICATION_ID=$(echo "$application" | ${pkgs.jq}/bin/jq -r '.id')

            if ! echo "$CONFIGURED_NAMES" | ${pkgs.jq}/bin/jq -e --arg name "$APPLICATION_NAME" 'index($name)' >/dev/null; then
              echo "Deleting application not in config: $APPLICATION_NAME (ID: $APPLICATION_ID)"
              ${
                mkSecureCurl cfg.config.apiKey {
                  url = "$BASE_URL/applications/$APPLICATION_ID";
                  method = "DELETE";
                  extraArgs = "-Sf";
                }
              } >/dev/null || echo "Warning: Failed to delete application $APPLICATION_NAME"
            fi
          done

          ${concatMapStringsSep "\n" (
            applicationConfig:
            let
              applicationName = applicationConfig.name;
              inherit (applicationConfig) implementationName;
              inherit (applicationConfig) apiKey;
              allOverrides = builtins.removeAttrs applicationConfig [
                "implementationName"
                "apiKey"
              ];
              fieldOverrides = lib.filterAttrs (
                name: value: value != null && !lib.hasPrefix "_" name
              ) allOverrides;
              fieldOverridesJson = builtins.toJSON fieldOverrides;

              jqSecrets = secrets.mkJqSecretArgs {
                inherit apiKey;
              };
            in
            ''
              echo "Processing application: ${applicationName}"

              apply_field_overrides() {
                local application_json="$1"
                local overrides="$2"

                echo "$application_json" | ${pkgs.jq}/bin/jq \
                  ${jqSecrets.flagsString} \
                  --argjson overrides "$overrides" '
                    .fields[] |= (if .name == "apiKey" then .value = ${jqSecrets.refs.apiKey} else . end)
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

              FIELD_OVERRIDES=${escapeShellArg fieldOverridesJson}

              EXISTING_APPLICATION=$(echo "$APPLICATIONS" | ${pkgs.jq}/bin/jq -r --arg name ${escapeShellArg applicationName} '.[] | select(.name == $name) | @json' || echo "")

              if [ -n "$EXISTING_APPLICATION" ]; then
                echo "Application ${applicationName} already exists, updating..."
                APPLICATION_ID=$(echo "$EXISTING_APPLICATION" | ${pkgs.jq}/bin/jq -r '.id')

                UPDATED_APPLICATION=$(apply_field_overrides "$EXISTING_APPLICATION" "$FIELD_OVERRIDES")

                RESPONSE_FILE=$(mktemp)
                set +e
                ${
                  mkSecureCurl cfg.config.apiKey {
                    url = "$BASE_URL/applications/$APPLICATION_ID";
                    method = "PUT";
                    headers = {
                      "Content-Type" = "application/json";
                    };
                    data = "$UPDATED_APPLICATION";
                    extraArgs = "-S --fail-with-body";
                  }
                } > "$RESPONSE_FILE" 2>&1
                CURL_EXIT=$?
                set -e
                if [ "$CURL_EXIT" -ne 0 ]; then
                  echo "Error: Updating application ${applicationName} failed (curl exit code: $CURL_EXIT)"
                  echo "Request body (secrets redacted):"
                  echo "$UPDATED_APPLICATION" | ${pkgs.jq}/bin/jq '(.fields[]? | select(.name == "apiKey") | .value) = "***"' 2>/dev/null || echo "$UPDATED_APPLICATION"
                  echo "Response:"
                  cat "$RESPONSE_FILE"
                  rm -f "$RESPONSE_FILE"
                  exit 1
                fi
                rm -f "$RESPONSE_FILE"

                echo "Application ${applicationName} updated"
              else
                echo "Application ${applicationName} does not exist, creating..."

                SCHEMA=$(echo "$SCHEMAS" | ${pkgs.jq}/bin/jq -r --arg implName ${escapeShellArg implementationName} '.[] | select(.implementationName == $implName) | @json' || echo "")

                if [ -z "$SCHEMA" ]; then
                  echo "Error: No schema found for application implementationName ${implementationName}"
                  exit 1
                fi

                NEW_APPLICATION=$(apply_field_overrides "$SCHEMA" "$FIELD_OVERRIDES")

                RESPONSE_FILE=$(mktemp)
                set +e
                ${
                  mkSecureCurl cfg.config.apiKey {
                    url = "$BASE_URL/applications";
                    method = "POST";
                    headers = {
                      "Content-Type" = "application/json";
                    };
                    data = "$NEW_APPLICATION";
                    extraArgs = "-S --fail-with-body";
                  }
                } > "$RESPONSE_FILE" 2>&1
                CURL_EXIT=$?
                set -e
                if [ "$CURL_EXIT" -ne 0 ]; then
                  echo "Error: Creating application ${applicationName} failed (curl exit code: $CURL_EXIT)"
                  echo "Request body (secrets redacted):"
                  echo "$NEW_APPLICATION" | ${pkgs.jq}/bin/jq '(.fields[]? | select(.name == "apiKey") | .value) = "***"' 2>/dev/null || echo "$NEW_APPLICATION"
                  echo "Response:"
                  cat "$RESPONSE_FILE"
                  rm -f "$RESPONSE_FILE"
                  exit 1
                fi
                rm -f "$RESPONSE_FILE"

                echo "Application ${applicationName} created"
              fi
            ''
          ) cfg.config.applications}

          echo "Prowlarr applications configuration complete"
        '';
      };
}

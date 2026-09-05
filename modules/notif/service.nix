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
  cfg = config.nixflix.notif;

  allNotifications = filter (n: n.enable) (
    builtins.attrValues (
      builtins.removeAttrs cfg [
        "extraNotifications"
        "enable"
      ]
    )
    ++ cfg.extraNotifications
  );

  arrServices = [
    "sonarr"
    "sonarr-anime"
    "radarr"
    "lidarr"
  ];

  notificationsFor = serviceName: filter (n: elem serviceName n.services) allNotifications;

  notificationDependencies =
    serviceName: unique (concatMap (n: n.dependencies) (notificationsFor serviceName));

  mkNotificationsService =
    serviceName:
    let
      serviceConfig = config.nixflix.${serviceName}.config;
      capitalizedName =
        toUpper (builtins.substring 0 1 serviceName) + builtins.substring 1 (-1) serviceName;

      notifications = map (
        n:
        builtins.removeAttrs n [
          "services"
          "dependencies"
        ]
      ) (notificationsFor serviceName);
    in
    {
      "${serviceName}-notifications" = {
        description = "Configure ${serviceName} notifications via API";
        after = [
          "${serviceName}.service"
          "${serviceName}-config.service"
        ]
        ++ notificationDependencies serviceName;
        requires = [
          "${serviceName}.service"
          "${serviceName}-config.service"
        ]
        ++ notificationDependencies serviceName;
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStartPre =
            "${pkgs.curl}/bin/curl --retry 30 --retry-delay 2 --retry-connrefused -so /dev/null"
            + " http://${
               config.nixflix.${serviceName}.connectionAddress
             }:${builtins.toString serviceConfig.hostConfig.port}${serviceConfig.hostConfig.urlBase}/api/${serviceConfig.apiVersion}/system/status";
        };

        script = ''
          set -eu

          BASE_URL="http://${
            config.nixflix.${serviceName}.connectionAddress
          }:${builtins.toString serviceConfig.hostConfig.port}${serviceConfig.hostConfig.urlBase}/api/${serviceConfig.apiVersion}"

          # Fetch all notification schemas
          echo "Fetching notification schemas..."
          SCHEMAS=$(${
            mkSecureCurl serviceConfig.apiKey {
              url = "$BASE_URL/notification/schema";
              extraArgs = "-S";
            }
          })

          # Fetch existing notifications
          echo "Fetching existing notifications..."
          NOTIFICATIONS=$(${
            mkSecureCurl serviceConfig.apiKey {
              url = "$BASE_URL/notification";
              extraArgs = "-S";
            }
          })

          # Build list of configured notification names
          CONFIGURED_NAMES=$(cat <<'EOF'
          ${builtins.toJSON (map (n: n.name) notifications)}
          EOF
          )

          # Delete notifications that are not in the configuration
          echo "Removing notifications not in configuration..."
          echo "$NOTIFICATIONS" | ${pkgs.jq}/bin/jq -r '.[] | @json' | while IFS= read -r notification; do
            NOTIFICATION_NAME=$(echo "$notification" | ${pkgs.jq}/bin/jq -r '.name')
            NOTIFICATION_ID=$(echo "$notification" | ${pkgs.jq}/bin/jq -r '.id')

            if ! echo "$CONFIGURED_NAMES" | ${pkgs.jq}/bin/jq -e --arg name "$NOTIFICATION_NAME" 'index($name)' >/dev/null 2>&1; then
              echo "Deleting notification not in config: $NOTIFICATION_NAME (ID: $NOTIFICATION_ID)"
              ${
                mkSecureCurl serviceConfig.apiKey {
                  url = "$BASE_URL/notification/$NOTIFICATION_ID";
                  method = "DELETE";
                  extraArgs = "-Sf";
                }
              } >/dev/null || echo "Warning: Failed to delete notification $NOTIFICATION_NAME"
            fi
          done

          ${concatMapStringsSep "\n" (
            notificationConfig:
            let
              notificationName = notificationConfig.name;
              inherit (notificationConfig) implementationName;
              apiKey = notificationConfig.apiKey or null;
              username = notificationConfig.username or null;
              password = notificationConfig.password or null;
              accessToken = notificationConfig.accessToken or null;
              allOverrides = builtins.removeAttrs notificationConfig [
                "implementationName"
                "apiKey"
                "username"
                "password"
                "accessToken"
              ];
              fieldOverrides = filterAttrs (name: value: value != null && !hasPrefix "_" name) allOverrides;
              fieldOverridesJson = builtins.toJSON fieldOverrides;

              jqSecrets = secrets.mkJqSecretArgs {
                apiKey = if apiKey == null then "" else apiKey;
                username = if username == null then "" else username;
                password = if password == null then "" else password;
                accessToken = if accessToken == null then "" else accessToken;
              };
            in
            ''
              echo "Processing notification: ${notificationName}"

              apply_field_overrides() {
                local notification_json="$1"
                local overrides="$2"

                echo "$notification_json" | ${pkgs.jq}/bin/jq \
                  ${jqSecrets.flagsString} \
                  --argjson overrides "$overrides" '
                    .fields[] |= (
                      if .name == "apiKey" and ${jqSecrets.refs.apiKey} != "" then .value = ${jqSecrets.refs.apiKey}
                      elif .name == "username" and ${jqSecrets.refs.username} != "" then .value = ${jqSecrets.refs.username}
                      elif .name == "password" and ${jqSecrets.refs.password} != "" then .value = ${jqSecrets.refs.password}
                      elif .name == "accessToken" and ${jqSecrets.refs.accessToken} != "" then .value = ${jqSecrets.refs.accessToken}
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

              EXISTING_NOTIFICATION=$(echo "$NOTIFICATIONS" | ${pkgs.jq}/bin/jq -r --arg name ${escapeShellArg notificationName} '.[] | select(.name == $name) | @json' || echo "")

              if [ -n "$EXISTING_NOTIFICATION" ]; then
                echo "Notification ${notificationName} already exists, updating..."
                NOTIFICATION_ID=$(echo "$EXISTING_NOTIFICATION" | ${pkgs.jq}/bin/jq -r '.id')

                UPDATED_NOTIFICATION=$(apply_field_overrides "$EXISTING_NOTIFICATION" "$FIELD_OVERRIDES")

                for _retry_attempt in $(seq 1 5); do
                  if ${
                    mkSecureCurl serviceConfig.apiKey {
                      url = "$BASE_URL/notification/$NOTIFICATION_ID";
                      method = "PUT";
                      headers = {
                        "Content-Type" = "application/json";
                      };
                      data = "$UPDATED_NOTIFICATION";
                      extraArgs = "-Sf";
                    }
                  } >/dev/null; then
                    break
                  fi
                  if [ "$_retry_attempt" -eq 5 ]; then
                    echo "Error: Failed to update notification ${notificationName} after 5 attempts"
                    exit 1
                  fi
                  echo "Attempt $_retry_attempt to update ${notificationName} failed, retrying in 1 second..."
                  sleep 1
                done

                echo "Notification ${notificationName} updated"
              else
                echo "Notification ${notificationName} does not exist, creating..."

                SCHEMA=$(echo "$SCHEMAS" | ${pkgs.jq}/bin/jq -r --arg implName ${escapeShellArg implementationName} '.[] | select(.implementationName == $implName) | @json' || echo "")

                if [ -z "$SCHEMA" ]; then
                  echo "Error: No schema found for notification implementationName ${implementationName}"
                  exit 1
                fi

                NEW_NOTIFICATION=$(apply_field_overrides "$SCHEMA" "$FIELD_OVERRIDES")

                for _retry_attempt in $(seq 1 5); do
                  if ${
                    mkSecureCurl serviceConfig.apiKey {
                      url = "$BASE_URL/notification";
                      method = "POST";
                      headers = {
                        "Content-Type" = "application/json";
                      };
                      data = "$NEW_NOTIFICATION";
                      extraArgs = "-Sf";
                    }
                  } >/dev/null; then
                    break
                  fi
                  if [ "$_retry_attempt" -eq 5 ]; then
                    echo "Error: Failed to create notification ${notificationName} after 5 attempts"
                    exit 1
                  fi
                  echo "Attempt $_retry_attempt to create ${notificationName} failed, retrying in 1 second..."
                  sleep 1
                done

                echo "Notification ${notificationName} created"
              fi
            ''
          ) notifications}

          echo "${capitalizedName} notifications configuration complete"
        '';
      };
    };

  enabledArrServices = filter (
    serviceName:
    config.nixflix.enable
    && notificationsFor serviceName != [ ]
    && (config.nixflix.${serviceName}.enable or false)
    && (config.nixflix.${serviceName}.config.apiKey or null) != null
  ) arrServices;
in
{
  config = mkIf (config.nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = !cfg.ntfy.enable || cfg.ntfy.topics != [ ];
        message = "nixflix.notif.ntfy.enable requires at least one nixflix.notif.ntfy.topics entry.";
      }
    ];

    systemd.services = mkMerge (map mkNotificationsService enabledArrServices);
  };
}

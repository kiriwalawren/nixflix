{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  inherit (config) nixflix;
  cfg = config.nixflix.jellyfin;

  mkSecureCurl = import ../../lib/mk-secure-curl.nix { inherit lib pkgs; };
  authUtil = import ./authUtil.nix { inherit lib pkgs cfg; };

  waitForApiScript = import ./waitForApiScript.nix {
    inherit pkgs;
    jellyfinCfg = cfg;
  };

  baseUrl =
    if cfg.network.baseUrl == "" then
      "http://127.0.0.1:${toString cfg.network.internalHttpPort}"
    else
      "http://127.0.0.1:${toString cfg.network.internalHttpPort}/${cfg.network.baseUrl}";

  enabledPlugins = filterAttrs (_name: p: p.enabled) cfg.plugins;

  configuredPluginsJson = builtins.toJSON (mapAttrs (_name: p: p.version) enabledPlugins);

  pluginsWithConfig = filterAttrs (
    _name: pluginCfg:
    removeAttrs pluginCfg [
      "version"
      "enabled"
    ] != { }
  ) enabledPlugins;

  pluginConfigFiles = mapAttrs (
    name: pluginCfg:
    pkgs.writeText "jellyfin-plugin-config-${name}.json" (
      builtins.toJSON (
        removeAttrs pluginCfg [
          "version"
          "enabled"
        ]
      )
    )
  ) pluginsWithConfig;
in
{
  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.services.jellyfin-plugins = {
      description = "Manage Jellyfin Plugins via API";
      after = [ "jellyfin-setup-wizard.service" ] ++ config.nixflix.serviceDependencies;
      requires = [ "jellyfin-setup-wizard.service" ] ++ config.nixflix.serviceDependencies;
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = 300;
      };

      script = ''
        set -eu

        BASE_URL="${baseUrl}"
        STATE_FILE="${cfg.dataDir}/nixflix-managed-plugins.json"

        echo "Managing Jellyfin plugins..."

        source ${authUtil.authScript}

        echo "Fetching available packages from $BASE_URL/Packages..."
        CATALOG_RESPONSE=$(${
          mkSecureCurl authUtil.token {
            url = "$BASE_URL/Packages";
            apiKeyHeader = "Authorization";
            extraArgs = "-w \"\\n%{http_code}\"";
          }
        })
        CATALOG_HTTP_CODE=$(echo "$CATALOG_RESPONSE" | tail -n1)
        CATALOG_JSON=$(echo "$CATALOG_RESPONSE" | sed '$d')

        if [ "$CATALOG_HTTP_CODE" -lt 200 ] || [ "$CATALOG_HTTP_CODE" -ge 300 ]; then
          echo "Failed to fetch package catalog (HTTP $CATALOG_HTTP_CODE)" >&2
          exit 1
        fi

        echo "Fetching installed plugins from $BASE_URL/Plugins..."
        PLUGINS_RESPONSE=$(${
          mkSecureCurl authUtil.token {
            url = "$BASE_URL/Plugins";
            apiKeyHeader = "Authorization";
            extraArgs = "-w \"\\n%{http_code}\"";
          }
        })
        PLUGINS_HTTP_CODE=$(echo "$PLUGINS_RESPONSE" | tail -n1)
        INSTALLED_JSON=$(echo "$PLUGINS_RESPONSE" | sed '$d')

        if [ "$PLUGINS_HTTP_CODE" -lt 200 ] || [ "$PLUGINS_HTTP_CODE" -ge 300 ]; then
          echo "Failed to fetch installed plugins (HTTP $PLUGINS_HTTP_CODE)" >&2
          exit 1
        fi

        CONFIGURED_PLUGINS='${configuredPluginsJson}'

        if [ -f "$STATE_FILE" ]; then
          PREVIOUS_MANAGED=$(cat "$STATE_FILE")
        else
          PREVIOUS_MANAGED="{}"
        fi

        CHANGED=false

        # Phase 1: Uninstall plugins that were managed but are no longer configured
        echo "Checking for plugins to remove..."
        while IFS= read -r plugin_name; do
          [ -z "$plugin_name" ] && continue

          PLUGIN_ID=$(echo "$INSTALLED_JSON" | ${pkgs.jq}/bin/jq -r --arg name "$plugin_name" \
            '.[] | select(.Name == $name) | .Id // empty')

          if [ -n "$PLUGIN_ID" ]; then
            echo "Removing plugin: $plugin_name (id: $PLUGIN_ID)"
            DELETE_RESPONSE=$(${
              mkSecureCurl authUtil.token {
                method = "DELETE";
                url = "$BASE_URL/Plugins/$PLUGIN_ID";
                apiKeyHeader = "Authorization";
                extraArgs = "-w \"\\n%{http_code}\"";
              }
            })
            DELETE_HTTP_CODE=$(echo "$DELETE_RESPONSE" | tail -n1)

            if [ "$DELETE_HTTP_CODE" -lt 200 ] || [ "$DELETE_HTTP_CODE" -ge 300 ]; then
              echo "Failed to remove plugin $plugin_name (HTTP $DELETE_HTTP_CODE)" >&2
              exit 1
            fi

            echo "Successfully removed plugin: $plugin_name"
            CHANGED=true
          else
            echo "Plugin $plugin_name was previously managed but is not installed, skipping"
          fi
        done < <(echo "$PREVIOUS_MANAGED" | ${pkgs.jq}/bin/jq -r \
          --argjson configured "$CONFIGURED_PLUGINS" \
          'keys[] | select(. as $k | $configured | has($k) | not)')

        # Phase 2: Install or update configured plugins
        echo "Checking for plugins to install or update..."
        while IFS=$'\t' read -r plugin_name plugin_version; do
          [ -z "$plugin_name" ] && continue

          PLUGIN_GUID=$(echo "$CATALOG_JSON" | ${pkgs.jq}/bin/jq -r --arg name "$plugin_name" \
            '.[] | select(.name == $name) | .guid // empty' | head -n1)

          if [ -z "$PLUGIN_GUID" ]; then
            echo "Error: Plugin '$plugin_name' not found in any configured repository" >&2
            exit 1
          fi

          INSTALLED_VERSION=$(echo "$INSTALLED_JSON" | ${pkgs.jq}/bin/jq -r --arg name "$plugin_name" \
            '.[] | select(.Name == $name) | .Version // empty')

          if [ -z "$INSTALLED_VERSION" ]; then
            echo "Installing plugin: $plugin_name version $plugin_version (guid: $PLUGIN_GUID)"
            INSTALL_RESPONSE=$(${
              mkSecureCurl authUtil.token {
                method = "POST";
                url = "$BASE_URL/Packages/Installed?assemblyGuid=$PLUGIN_GUID&version=$plugin_version";
                apiKeyHeader = "Authorization";
                extraArgs = "-w \"\\n%{http_code}\"";
              }
            })
            INSTALL_HTTP_CODE=$(echo "$INSTALL_RESPONSE" | tail -n1)

            if [ "$INSTALL_HTTP_CODE" -lt 200 ] || [ "$INSTALL_HTTP_CODE" -ge 300 ]; then
              echo "Failed to install plugin $plugin_name $plugin_version (HTTP $INSTALL_HTTP_CODE)" >&2
              exit 1
            fi

            echo "Successfully queued install: $plugin_name $plugin_version"
            CHANGED=true
          elif [ "$INSTALLED_VERSION" != "$plugin_version" ]; then
            echo "Updating plugin: $plugin_name from $INSTALLED_VERSION to $plugin_version"
            INSTALL_RESPONSE=$(${
              mkSecureCurl authUtil.token {
                method = "POST";
                url = "$BASE_URL/Packages/Installed?assemblyGuid=$PLUGIN_GUID&version=$plugin_version";
                apiKeyHeader = "Authorization";
                extraArgs = "-w \"\\n%{http_code}\"";
              }
            })
            INSTALL_HTTP_CODE=$(echo "$INSTALL_RESPONSE" | tail -n1)

            if [ "$INSTALL_HTTP_CODE" -lt 200 ] || [ "$INSTALL_HTTP_CODE" -ge 300 ]; then
              echo "Failed to update plugin $plugin_name to $plugin_version (HTTP $INSTALL_HTTP_CODE)" >&2
              exit 1
            fi

            echo "Successfully queued update: $plugin_name $plugin_version"
            CHANGED=true
          else
            echo "Plugin $plugin_name is already at version $plugin_version, skipping"
          fi
        done < <(echo "$CONFIGURED_PLUGINS" | ${pkgs.jq}/bin/jq -r 'to_entries[] | "\(.key)\t\(.value)"')

        # Phase 3: Restart Jellyfin if changes were made, then persist state.
        # State is written AFTER a successful restart so that a failed restart
        # leaves the previous state intact and the next run will retry.
        if [ "$CHANGED" = "true" ]; then
          echo "Plugin changes detected, restarting Jellyfin to apply..."
          systemctl restart jellyfin
          echo "Waiting for Jellyfin to be ready after restart..."
          ${waitForApiScript}
          echo "Jellyfin is ready after plugin restart"
        else
          echo "No plugin changes detected, skipping restart"
        fi

        echo "$CONFIGURED_PLUGINS" > "$STATE_FILE"
        echo "State file updated: $STATE_FILE"

        # Phase 4: Apply plugin-specific configurations
        ${
          if pluginsWithConfig != { } then
            ''
              echo "Applying plugin configurations..."

              # Re-fetch installed plugins to get current runtime IDs
              PLUGINS_RESPONSE=$(${
                mkSecureCurl authUtil.token {
                  url = "$BASE_URL/Plugins";
                  apiKeyHeader = "Authorization";
                  extraArgs = "-w \"\\n%{http_code}\"";
                }
              })
              PLUGINS_HTTP_CODE=$(echo "$PLUGINS_RESPONSE" | tail -n1)
              INSTALLED_JSON=$(echo "$PLUGINS_RESPONSE" | sed '$d')

              if [ "$PLUGINS_HTTP_CODE" -lt 200 ] || [ "$PLUGINS_HTTP_CODE" -ge 300 ]; then
                echo "Failed to fetch installed plugins for configuration (HTTP $PLUGINS_HTTP_CODE)" >&2
                exit 1
              fi

              ${concatStringsSep "\n" (
                mapAttrsToList (pluginName: configFile: ''
                  echo "Configuring plugin: ${pluginName}..."
                  PLUGIN_ID=$(echo "$INSTALLED_JSON" | ${pkgs.jq}/bin/jq -r \
                    --arg name "${pluginName}" '.[] | select(.Name == $name) | .Id // empty')

                  if [ -z "$PLUGIN_ID" ]; then
                    echo "Warning: Plugin ${pluginName} not found in installed plugins, skipping configuration" >&2
                  else
                    CONFIG_RESPONSE=$(${
                      mkSecureCurl authUtil.token {
                        method = "POST";
                        url = "$BASE_URL/Plugins/$PLUGIN_ID/Configuration";
                        apiKeyHeader = "Authorization";
                        headers = {
                          "Content-Type" = "application/json";
                        };
                        data = "@${configFile}";
                        extraArgs = "-w \"\\n%{http_code}\"";
                      }
                    })
                    CONFIG_HTTP_CODE=$(echo "$CONFIG_RESPONSE" | tail -n1)

                    if [ "$CONFIG_HTTP_CODE" -lt 200 ] || [ "$CONFIG_HTTP_CODE" -ge 300 ]; then
                      echo "Failed to configure plugin ${pluginName} (HTTP $CONFIG_HTTP_CODE)" >&2
                      exit 1
                    fi

                    echo "Successfully configured plugin: ${pluginName}"
                  fi
                '') pluginConfigFiles
              )}
            ''
          else
            ""
        }

        echo "Plugin management completed successfully"
      '';
    };
  };
}

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
  secrets = import ../../lib/secrets/default.nix { inherit lib; };

  waitForApiScript = import ./waitForApiScript.nix {
    inherit pkgs;
    jellyfinCfg = cfg;
  };

  pluginResolution = import ./resolvePlugins.nix {
    inherit lib pkgs;
    jellyfinVersion = cfg.package.version;
    inherit (cfg.system) pluginRepositories;
    inherit (cfg) plugins;
  };

  baseUrl =
    if cfg.network.baseUrl == "" then
      "http://127.0.0.1:${toString cfg.network.internalHttpPort}"
    else
      "http://127.0.0.1:${toString cfg.network.internalHttpPort}/${cfg.network.baseUrl}";

  managedPlugins = filterAttrs (
    _name: pluginCfg: pluginCfg.package != null
  ) pluginResolution.resolvedEnabledPlugins;

  pluginDirName = pluginResolution.packagePluginDirName;

  configuredManagedPluginsJson = builtins.toJSON (
    mapAttrs (_name: pluginCfg: {
      dir = pluginDirName pluginCfg.package;
      path = toString pluginCfg.package;
    }) managedPlugins
  );

  pluginsWithConfig = filterAttrs (_name: pluginCfg: pluginCfg.config != { }) managedPlugins;

  pluginConfigData = mapAttrs (
    name: pluginCfg:
    let
      rawConfig = pluginCfg.config;
      lookupName = pluginCfg.apiName;
    in
    {
      plainFile = pkgs.writeText "jellyfin-plugin-config-${name}.json" (
        builtins.toJSON (secrets.stripSecretRefs rawConfig)
      );
      jqSecrets = secrets.mkNestedJqSecretArgs rawConfig;
      inherit lookupName;
    }
  ) pluginsWithConfig;
in
{
  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.tmpfiles.settings."10-jellyfin"."${cfg.dataDir}/plugins".d = {
      mode = "0755";
      inherit (cfg) user;
      inherit (cfg) group;
    };

    systemd.services.jellyfin-plugins = {
      description = "Manage Jellyfin plugins";
      after = [ "jellyfin-system-config.service" ] ++ config.nixflix.serviceDependencies;
      requires = [ "jellyfin-system-config.service" ] ++ config.nixflix.serviceDependencies;
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = 300;
      };

      script = ''
        set -euo pipefail

        BASE_URL="${baseUrl}"
        PLUGIN_DIR='${cfg.dataDir}/plugins'
        STATE_FILE="${cfg.dataDir}/nixflix-managed-plugins.json"
        LEGACY_MANIFEST="$PLUGIN_DIR/.nixflix-managed"
        CONFIGURED_PLUGINS='${configuredManagedPluginsJson}'

        fetch_installed_plugins() {
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
        }

        start_jellyfin() {
          echo "Starting Jellyfin after syncing plugins..."
          systemctl start jellyfin
          echo "Waiting for Jellyfin to be ready after plugin sync..."
          ${waitForApiScript}
          echo "Jellyfin is ready after plugin sync"
        }

        ensure_jellyfin_ready() {
          if systemctl is-active --quiet jellyfin; then
            ${waitForApiScript}
          else
            start_jellyfin
          fi
        }

        load_previous_state() {
          if [ -f "$STATE_FILE" ]; then
            ${pkgs.jq}/bin/jq -c 'with_entries(.value |= if type == "string" then { dir: ., path: null } elif type == "object" then { dir: .dir // null, path: .path // null } else . end)' "$STATE_FILE"
          else
            printf '{}'
          fi
        }

        previous_dirs() {
          echo "$PREVIOUS_STATE" | ${pkgs.jq}/bin/jq -r 'to_entries[] | .value.dir // empty'

          if [ -f "$LEGACY_MANIFEST" ]; then
            ${pkgs.coreutils}/bin/cat "$LEGACY_MANIFEST"
          fi
        }

        sync_plugins() {
          ${pkgs.coreutils}/bin/mkdir -p "$PLUGIN_DIR"
          ${pkgs.coreutils}/bin/chown '${cfg.user}:${cfg.group}' "$PLUGIN_DIR"

          while IFS= read -r old_dir; do
            [ -z "$old_dir" ] && continue

            if ! echo "$CONFIGURED_PLUGINS" | ${pkgs.jq}/bin/jq -e --arg dir "$old_dir" \
              'to_entries[] | select(.value.dir == $dir)' >/dev/null 2>&1; then
              if [ -d "$PLUGIN_DIR/$old_dir" ]; then
                ${pkgs.coreutils}/bin/rm -rf "$PLUGIN_DIR/$old_dir"
                echo "Removed managed plugin directory: $old_dir"
              fi
            fi
          done < <(previous_dirs | sed '/^$/d' | sort -u)

          ${concatStringsSep "\n" (
            mapAttrsToList (
              pluginName: pluginCfg:
              let
                dirName = pluginDirName pluginCfg.package;
              in
              ''
                echo "Syncing packaged plugin: ${pluginName}"
                TARGET="$PLUGIN_DIR/${dirName}"
                ${pkgs.coreutils}/bin/rm -rf "$TARGET"
                ${pkgs.coreutils}/bin/mkdir -p "$TARGET"
                ${pkgs.coreutils}/bin/cp -a '${pluginCfg.package}'/. "$TARGET/"
                ${pkgs.coreutils}/bin/chown -R '${cfg.user}:${cfg.group}' "$TARGET"
                ${pkgs.coreutils}/bin/chmod -R u+w "$TARGET"
              ''
            ) managedPlugins
          )}

          ${pkgs.coreutils}/bin/rm -f "$LEGACY_MANIFEST"
        }

        echo "Managing Jellyfin plugins..."

        PREVIOUS_STATE=$(load_previous_state)
        CURRENT_STATE=$(echo "$CONFIGURED_PLUGINS" | ${pkgs.jq}/bin/jq -cS .)
        PREVIOUS_NORMALIZED=$(echo "$PREVIOUS_STATE" | ${pkgs.jq}/bin/jq -cS 'map_values({ dir: .dir // null, path: .path // null })')

        if [ "$PREVIOUS_NORMALIZED" != "$CURRENT_STATE" ] || [ -f "$LEGACY_MANIFEST" ]; then
          echo "Plugin file changes detected, syncing plugin directories..."

          if systemctl is-active --quiet jellyfin; then
            systemctl stop jellyfin
          fi

          sync_plugins
          start_jellyfin
        else
          echo "No plugin file changes detected"
        fi

        echo "$CONFIGURED_PLUGINS" > "$STATE_FILE"
        echo "State file updated: $STATE_FILE"

        ${
          if pluginsWithConfig != { } then
            ''
              ensure_jellyfin_ready
              source ${authUtil.authScript}

              echo "Applying plugin configurations..."
              fetch_installed_plugins

              ${concatStringsSep "\n" (
                mapAttrsToList (
                  pluginName: configData:
                  let
                    secretUpdates = concatStringsSep " | " configData.jqSecrets.assignments;
                    jqFilter =
                      if configData.jqSecrets.hasSecrets then ". * $plain | ${secretUpdates}" else ". * $plain";
                  in
                  ''
                    echo "Configuring plugin: ${pluginName}..."
                    PLUGIN_ID=$(echo "$INSTALLED_JSON" | ${pkgs.jq}/bin/jq -r \
                      --arg name "${configData.lookupName}" '.[] | select(.Name == $name) | .Id // empty')

                    if [ -z "$PLUGIN_ID" ]; then
                      echo "Warning: Plugin ${pluginName} not found in installed plugins, skipping configuration" >&2
                    else
                      CURRENT_CONFIG=$(${
                        mkSecureCurl authUtil.token {
                          url = "$BASE_URL/Plugins/$PLUGIN_ID/Configuration";
                          apiKeyHeader = "Authorization";
                        }
                      })

                      DESIRED_PLAIN=$(${pkgs.coreutils}/bin/cat ${configData.plainFile})
                      MERGED_CONFIG=$(echo "$CURRENT_CONFIG" | \
                        ${pkgs.jq}/bin/jq ${configData.jqSecrets.flagsString} \
                        --argjson plain "$DESIRED_PLAIN" \
                        '${jqFilter}')

                      CONFIG_RESPONSE=$(${
                        mkSecureCurl authUtil.token {
                          method = "POST";
                          url = "$BASE_URL/Plugins/$PLUGIN_ID/Configuration";
                          apiKeyHeader = "Authorization";
                          headers = {
                            "Content-Type" = "application/json";
                          };
                          data = "$MERGED_CONFIG";
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
                  ''
                ) pluginConfigData
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

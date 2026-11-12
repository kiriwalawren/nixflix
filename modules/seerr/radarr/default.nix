{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  secrets = import ../../../lib/secrets { inherit lib; };
  inherit (config) nixflix;
  cfg = nixflix.seerr;
  mkSecureCurl = import ../../../lib/mk-secure-curl.nix { inherit lib pkgs; };
  baseUrl = "http://${cfg.connectionAddress}:${toString cfg.port}";

  sanitizeName = name: builtins.replaceStrings [ " " "-" ] [ "_" "_" ] name;

  syncMode = import ../../../lib/sync-mode.nix { inherit lib pkgs; };
  mode = cfg.syncMode.radarr;

  getServers = ''
    EXISTING_SERVERS=$(${
      mkSecureCurl cfg.apiKey {
        url = "$BASE_URL/api/v1/settings/radarr";
        extraArgs = "--max-time 30";
      }
    })
  '';

  servers = syncMode.mkPrune {
    inherit mode;
    unit = "seerr-radarr";
    what = "Radarr servers";
    option = "nixflix.seerr.syncMode.radarr";
    live = "EXISTING_SERVERS";
    declared = attrNames cfg.radarr;
    # The delete loop's `[.name] | inside($configured[0])` is jq containment,
    # which matches strings by SUBSTRING: a live "Radarr" or "4K" survives when
    # "Radarr 4K" is declared. refuse and keep flag the same servers it deletes.
    select = "[.name] | inside($declared) | not";
    onDelete = ''
      SERVERS_TO_DELETE=$(echo "$EXISTING_SERVERS" | ${pkgs.jq}/bin/jq -r \
        --slurpfile configured "$CONFIGURED_NAMES" \
        '.[] | select([.name] | inside($configured[0]) | not) | .id')

      for server_id in $SERVERS_TO_DELETE; do
        echo "Deleting Radarr server (ID: $server_id)..."
        ${
          mkSecureCurl cfg.apiKey {
            url = "$BASE_URL/api/v1/settings/radarr/$server_id";
            method = "DELETE";
            extraArgs = "-f --max-time 30";
          }
        } >/dev/null
      done
    '';
  };

  mkRadarrConfigScript =
    radarrName: radarrCfg:
    let
      jqRadarrSecrets = secrets.mkJqSecretArgs {
        apiKey._secret = "/run/credentials/seerr-radarr.service/radarr-${sanitizeName radarrName}-apikey";
      };
    in
    ''
      echo "Configuring Radarr instance: ${radarrName}"

      # Test connection and get profiles
      TEST_PAYLOAD=$(${pkgs.jq}/bin/jq -n \
        ${jqRadarrSecrets.flagsString} \
        --arg hostname "${radarrCfg.hostname}" \
        --arg port "${toString radarrCfg.port}" \
        --arg useSsl "${boolToString radarrCfg.useSsl}" \
        --arg baseUrl "${radarrCfg.baseUrl}" \
        '{
          hostname: $hostname,
          port: ($port | tonumber),
          apiKey: ${jqRadarrSecrets.refs.apiKey},
          useSsl: ($useSsl == "true"),
          baseUrl: $baseUrl
        }')

      echo "Testing Radarr connection..."
      TEST_RESPONSE=$(printf '%s' "$TEST_PAYLOAD" | ${
        mkSecureCurl cfg.apiKey {
          url = "$BASE_URL/api/v1/settings/radarr/test";
          method = "POST";
          headers."Content-Type" = "application/json";
          data = "@-";
          extraArgs = ''--max-time 30 -w "\n%{http_code}"'';
        }
      })

      TEST_HTTP_CODE=$(echo "$TEST_RESPONSE" | tail -n1)
      TEST_BODY=$(echo "$TEST_RESPONSE" | sed '$d')

      if [ "$TEST_HTTP_CODE" != "200" ]; then
        echo "Radarr connection test failed (HTTP $TEST_HTTP_CODE)" >&2
        echo "$TEST_BODY" >&2
        exit 1
      fi

      echo "Radarr connection successful"

      # Auto-detect profile ID from profile name
      ${
        if radarrCfg.activeProfileName != null then
          ''
            PROFILE_ID=$(echo "$TEST_BODY" | ${pkgs.jq}/bin/jq -r \
              --arg name ${escapeShellArg radarrCfg.activeProfileName} '.profiles[] | select(.name == $name) | .id')
            PROFILE_NAME="${radarrCfg.activeProfileName}"
          ''
        else
          ''
            # Use first available profile
            PROFILE_ID=$(echo "$TEST_BODY" | ${pkgs.jq}/bin/jq -r '.profiles[0].id')
            PROFILE_NAME=$(echo "$TEST_BODY" | ${pkgs.jq}/bin/jq -r '.profiles[0].name')
          ''
      }

      if [ -z "$PROFILE_ID" ] || [ "$PROFILE_ID" = "null" ]; then
        echo "Could not find quality profile${
          if radarrCfg.activeProfileName != null then " '${radarrCfg.activeProfileName}'" else ""
        }" >&2
        echo "Available profiles:" >&2
        echo "$TEST_BODY" | ${pkgs.jq}/bin/jq -r '.profiles[] | "  - \(.name)"' >&2
        exit 1
      fi

      echo "Using quality profile: $PROFILE_NAME (ID: $PROFILE_ID)"

      # Check if server already exists
      EXISTING_SERVERS=$(${
        mkSecureCurl cfg.apiKey {
          url = "$BASE_URL/api/v1/settings/radarr";
          extraArgs = "--max-time 30";
        }
      })

      EXISTING_ID=$(echo "$EXISTING_SERVERS" | ${pkgs.jq}/bin/jq -r \
        --arg name ${escapeShellArg radarrName} '.[] | select(.name == $name) | .id')

      # Build server configuration
      SERVER_CONFIG=$(${pkgs.jq}/bin/jq -n \
        ${jqRadarrSecrets.flagsString} \
        --arg name "${radarrName}" \
        --arg hostname "${radarrCfg.hostname}" \
        --arg port "${toString radarrCfg.port}" \
        --arg useSsl "${boolToString radarrCfg.useSsl}" \
        --arg baseUrl "${radarrCfg.baseUrl}" \
        --arg profileId "$PROFILE_ID" \
        --arg profileName "$PROFILE_NAME" \
        --arg directory "${radarrCfg.activeDirectory}" \
        --arg is4k "${boolToString radarrCfg.is4k}" \
        --arg minimumAvailability "${radarrCfg.minimumAvailability}" \
        --arg isDefault "${boolToString radarrCfg.isDefault}" \
        --arg externalUrl "${radarrCfg.externalUrl}" \
        --arg syncEnabled "${boolToString radarrCfg.syncEnabled}" \
        --arg preventSearch "${boolToString radarrCfg.preventSearch}" \
        '{
          name: $name,
          hostname: $hostname,
          port: ($port | tonumber),
          apiKey: ${jqRadarrSecrets.refs.apiKey},
          useSsl: ($useSsl == "true"),
          baseUrl: $baseUrl,
          activeProfileId: ($profileId | tonumber),
          activeProfileName: $profileName,
          activeDirectory: $directory,
          is4k: ($is4k == "true"),
          minimumAvailability: $minimumAvailability,
          isDefault: ($isDefault == "true"),
          externalUrl: $externalUrl,
          syncEnabled: ($syncEnabled == "true"),
          preventSearch: ($preventSearch == "true")
        }')

      if [ -n "$EXISTING_ID" ] && [ "$EXISTING_ID" != "null" ]; then
        echo "Updating existing Radarr instance (ID: $EXISTING_ID)..."
        UPDATE_RESPONSE=$(printf '%s' "$SERVER_CONFIG" | ${
          mkSecureCurl cfg.apiKey {
            url = "$BASE_URL/api/v1/settings/radarr/$EXISTING_ID";
            method = "PUT";
            headers."Content-Type" = "application/json";
            data = "@-";
            extraArgs = ''--max-time 30 -w "\n%{http_code}"'';
          }
        })

        UPDATE_HTTP_CODE=$(echo "$UPDATE_RESPONSE" | tail -n1)
        if [ "$UPDATE_HTTP_CODE" != "200" ] && [ "$UPDATE_HTTP_CODE" != "201" ]; then
          echo "Failed to update Radarr instance (HTTP $UPDATE_HTTP_CODE)" >&2
          echo "$UPDATE_RESPONSE" | head -n-1 >&2
          exit 1
        fi
        echo "Radarr instance updated"
      else
        echo "Creating new Radarr instance..."
        CREATE_RESPONSE=$(printf '%s' "$SERVER_CONFIG" | ${
          mkSecureCurl cfg.apiKey {
            url = "$BASE_URL/api/v1/settings/radarr";
            method = "POST";
            headers."Content-Type" = "application/json";
            data = "@-";
            extraArgs = ''--max-time 30 -w "\n%{http_code}"'';
          }
        })

        CREATE_HTTP_CODE=$(echo "$CREATE_RESPONSE" | tail -n1)
        if [ "$CREATE_HTTP_CODE" != "200" ] && [ "$CREATE_HTTP_CODE" != "201" ]; then
          echo "Failed to create Radarr instance (HTTP $CREATE_HTTP_CODE)" >&2
          echo "$CREATE_RESPONSE" | head -n-1 >&2
          exit 1
        fi
        echo "Radarr instance created"
      fi
    '';
in
{
  imports = [ ./options.nix ];

  config = mkIf (nixflix.enable && cfg.enable && cfg.radarr != { }) {
    systemd.services.seerr-radarr = {
      description = "Configure Seerr Radarr integration";
      after = [
        "seerr-libraries.service"
      ]
      ++ optional nixflix.radarr.enable "radarr-config.service"
      ++ optional nixflix.recyclarr.enable "recyclarr.service"
      ++ optional (
        nixflix.recyclarr.enable && nixflix.recyclarr.cleanupUnmanagedProfiles.enable
      ) "recyclarr-cleanup-profiles.service";

      wants = optional nixflix.recyclarr.enable "recyclarr.service";

      requires = [
        "seerr-libraries.service"
      ]
      ++ optional nixflix.radarr.enable "radarr-config.service"
      ++ optional (
        nixflix.recyclarr.enable && nixflix.recyclarr.cleanupUnmanagedProfiles.enable
      ) "recyclarr-cleanup-profiles.service";

      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        LoadCredential = mapAttrsToList (
          name: r:
          "radarr-${sanitizeName name}-apikey:${
            if secrets.isSecretRef r.apiKey then
              r.apiKey._secret
            else
              pkgs.writeText "radarr-${sanitizeName name}-inline-key" r.apiKey
          }"
        ) cfg.radarr;
      };

      script = ''
        set -euo pipefail

        BASE_URL="${baseUrl}"
        ${optionalString (mode == "refuse") ''
          # Read the live servers before any change so a refused sync changes nothing
          ${getServers}
          ${servers.guard}
          ${syncMode.refuseCheckpoint}
        ''}
        # Configure each Radarr instance
        ${concatStringsSep "\n" (mapAttrsToList mkRadarrConfigScript cfg.radarr)}

        # Delete servers not in configuration
        CONFIGURED_NAMES="${pkgs.writeText "radarr-names.json" (builtins.toJSON (attrNames cfg.radarr))}"

        ${getServers}
        ${servers.prune}
        echo "Radarr configuration completed"
      '';
    };
  };
}

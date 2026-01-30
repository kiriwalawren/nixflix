{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  secrets = import ../lib/secrets {inherit lib;};
  inherit (config) nixflix;
  cfg = nixflix.jellyseerr;
  jellyfinCfg = nixflix.jellyfin;
  authUtil = import ./authUtil.nix {inherit lib pkgs cfg jellyfinCfg;};
  baseUrl = "http://127.0.0.1:${toString cfg.port}";

  sanitizeName = name: builtins.replaceStrings [" " "-"] ["_" "_"] name;

  mkSonarrConfigScript = sonarrName: sonarrCfg: ''
    echo "Configuring Sonarr instance: ${sonarrName}"

    SONARR_API_KEY=$(cat "$CREDENTIALS_DIRECTORY/sonarr-${sanitizeName sonarrName}-apikey")

    # Test connection and get profiles
    TEST_PAYLOAD=$(${pkgs.jq}/bin/jq -n \
      --arg hostname "${sonarrCfg.hostname}" \
      --arg port "${toString sonarrCfg.port}" \
      --arg apiKey "$SONARR_API_KEY" \
      --arg useSsl "${boolToString sonarrCfg.useSsl}" \
      --arg baseUrl "${sonarrCfg.baseUrl}" \
      '{
        hostname: $hostname,
        port: ($port | tonumber),
        apiKey: $apiKey,
        useSsl: ($useSsl == "true"),
        baseUrl: $baseUrl
      }')

    echo "Testing Sonarr connection..."
    TEST_RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST \
      -b "${authUtil.cookieFile}" \
      -H "Content-Type: application/json" \
      -d "$TEST_PAYLOAD" \
      -w "\n%{http_code}" \
      "$BASE_URL/api/v1/settings/sonarr/test")

    TEST_HTTP_CODE=$(echo "$TEST_RESPONSE" | tail -n1)
    TEST_BODY=$(echo "$TEST_RESPONSE" | sed '$d')

    if [ "$TEST_HTTP_CODE" != "200" ]; then
      echo "Sonarr connection test failed (HTTP $TEST_HTTP_CODE)" >&2
      echo "$TEST_BODY" >&2
      exit 1
    fi

    echo "Sonarr connection successful"

    # Auto-detect profile ID from profile name
    ${
      if sonarrCfg.activeProfileName != null
      then ''
        PROFILE_ID=$(echo "$TEST_BODY" | ${pkgs.jq}/bin/jq -r \
          '.profiles[] | select(.name == "${sonarrCfg.activeProfileName}") | .id')
        PROFILE_NAME="${sonarrCfg.activeProfileName}"
      ''
      else ''
        # Use first available profile
        PROFILE_ID=$(echo "$TEST_BODY" | ${pkgs.jq}/bin/jq -r '.profiles[0].id')
        PROFILE_NAME=$(echo "$TEST_BODY" | ${pkgs.jq}/bin/jq -r '.profiles[0].name')
      ''
    }

    if [ -z "$PROFILE_ID" ] || [ "$PROFILE_ID" = "null" ]; then
      echo "Could not find quality profile${
      if sonarrCfg.activeProfileName != null
      then " '${sonarrCfg.activeProfileName}'"
      else ""
    }" >&2
      echo "Available profiles:" >&2
      echo "$TEST_BODY" | ${pkgs.jq}/bin/jq -r '.profiles[] | "  - \(.name)"' >&2
      exit 1
    fi

    echo "Using quality profile: $PROFILE_NAME (ID: $PROFILE_ID)"

    # Auto-detect anime profile ID if specified
    ${
      if sonarrCfg.activeAnimeProfileName != null
      then ''
        ANIME_PROFILE_ID=$(echo "$TEST_BODY" | ${pkgs.jq}/bin/jq -r \
          '.profiles[] | select(.name == "${sonarrCfg.activeAnimeProfileName}") | .id')
        ANIME_PROFILE_NAME="${sonarrCfg.activeAnimeProfileName}"

        if [ -z "$ANIME_PROFILE_ID" ] || [ "$ANIME_PROFILE_ID" = "null" ]; then
          echo "Warning: Could not find anime quality profile '${sonarrCfg.activeAnimeProfileName}', using regular profile" >&2
          ANIME_PROFILE_ID="$PROFILE_ID"
          ANIME_PROFILE_NAME="$PROFILE_NAME"
        else
          echo "Using anime quality profile: $ANIME_PROFILE_NAME (ID: $ANIME_PROFILE_ID)"
        fi
      ''
      else ''
        # Use same profile for anime as regular
        ANIME_PROFILE_ID="$PROFILE_ID"
        ANIME_PROFILE_NAME="$PROFILE_NAME"
      ''
    }

    # Check if server already exists
    EXISTING_SERVERS=$(${pkgs.curl}/bin/curl -s \
      -b "${authUtil.cookieFile}" \
      "$BASE_URL/api/v1/settings/sonarr")

    EXISTING_ID=$(echo "$EXISTING_SERVERS" | ${pkgs.jq}/bin/jq -r \
      '.[] | select(.name == "${sonarrName}") | .id')

    # Build server configuration
    SERVER_CONFIG=$(${pkgs.jq}/bin/jq -n \
      --arg name "${sonarrName}" \
      --arg hostname "${sonarrCfg.hostname}" \
      --arg port "${toString sonarrCfg.port}" \
      --arg apiKey "$SONARR_API_KEY" \
      --arg useSsl "${boolToString sonarrCfg.useSsl}" \
      --arg baseUrl "${sonarrCfg.baseUrl}" \
      --arg profileId "$PROFILE_ID" \
      --arg profileName "$PROFILE_NAME" \
      --arg directory "${sonarrCfg.activeDirectory}" \
      --arg animeProfileId "$ANIME_PROFILE_ID" \
      --arg animeProfileName "$ANIME_PROFILE_NAME" \
      --arg animeDirectory "${sonarrCfg.activeAnimeDirectory}" \
      --arg seriesType "${sonarrCfg.seriesType}" \
      --arg animeSeriesType "${sonarrCfg.animeSeriesType}" \
      --arg enableSeasonFolders "${boolToString sonarrCfg.enableSeasonFolders}" \
      --arg is4k "${boolToString sonarrCfg.is4k}" \
      --arg isDefault "${boolToString sonarrCfg.isDefault}" \
      --arg externalUrl "${sonarrCfg.externalUrl}" \
      --arg syncEnabled "${boolToString sonarrCfg.syncEnabled}" \
      --arg preventSearch "${boolToString sonarrCfg.preventSearch}" \
      '{
        name: $name,
        hostname: $hostname,
        port: ($port | tonumber),
        apiKey: $apiKey,
        useSsl: ($useSsl == "true"),
        baseUrl: $baseUrl,
        activeProfileId: ($profileId | tonumber),
        activeProfileName: $profileName,
        activeDirectory: $directory,
        activeAnimeProfileId: ($animeProfileId | tonumber),
        activeAnimeProfileName: $animeProfileName,
        activeAnimeDirectory: $animeDirectory,
        seriesType: $seriesType,
        animeSeriesType: $animeSeriesType,
        enableSeasonFolders: ($enableSeasonFolders == "true"),
        is4k: ($is4k == "true"),
        isDefault: ($isDefault == "true"),
        externalUrl: $externalUrl,
        syncEnabled: ($syncEnabled == "true"),
        preventSearch: ($preventSearch == "true")
      }')

    if [ -n "$EXISTING_ID" ] && [ "$EXISTING_ID" != "null" ]; then
      echo "Updating existing Sonarr instance (ID: $EXISTING_ID)..."
      UPDATE_RESPONSE=$(${pkgs.curl}/bin/curl -s -X PUT \
        -b "${authUtil.cookieFile}" \
        -H "Content-Type: application/json" \
        -d "$SERVER_CONFIG" \
        -w "\n%{http_code}" \
        "$BASE_URL/api/v1/settings/sonarr/$EXISTING_ID")

      UPDATE_HTTP_CODE=$(echo "$UPDATE_RESPONSE" | tail -n1)
      if [ "$UPDATE_HTTP_CODE" != "200" ] && [ "$UPDATE_HTTP_CODE" != "201" ]; then
        echo "Failed to update Sonarr instance (HTTP $UPDATE_HTTP_CODE)" >&2
        echo "$UPDATE_RESPONSE" | head -n-1 >&2
        exit 1
      fi
      echo "Sonarr instance updated"
    else
      echo "Creating new Sonarr instance..."
      CREATE_RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST \
        -b "${authUtil.cookieFile}" \
        -H "Content-Type: application/json" \
        -d "$SERVER_CONFIG" \
        -w "\n%{http_code}" \
        "$BASE_URL/api/v1/settings/sonarr")

      CREATE_HTTP_CODE=$(echo "$CREATE_RESPONSE" | tail -n1)
      if [ "$CREATE_HTTP_CODE" != "200" ] && [ "$CREATE_HTTP_CODE" != "201" ]; then
        echo "Failed to create Sonarr instance (HTTP $CREATE_HTTP_CODE)" >&2
        echo "$CREATE_RESPONSE" | head -n-1 >&2
        exit 1
      fi
      echo "Sonarr instance created"
    fi
  '';
in {
  config = mkIf (nixflix.enable && cfg.enable && cfg.sonarr != {}) {
    systemd.services.jellyseerr-sonarr = {
      description = "Configure Jellyseerr Sonarr integration";
      after =
        ["jellyseerr-setup.service"]
        ++ optional nixflix.recyclarr.enable "recyclarr.service"
        ++ optional nixflix.sonarr.enable "sonarr-config.service"
        ++ optional (nixflix.sonarr-anime.enable or false) "sonarr-anime-config.service";
      requires =
        ["jellyseerr-setup.service"]
        ++ optional nixflix.recyclarr.enable "recyclarr.service"
        ++ optional nixflix.sonarr.enable "sonarr-config.service"
        ++ optional (nixflix.sonarr-anime.enable or false) "sonarr-anime-config.service";
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        LoadCredential =
          mapAttrsToList (
            name: s: "sonarr-${sanitizeName name}-apikey:${
              if secrets.isSecretRef s.apiKey
              then s.apiKey._secret
              else pkgs.writeText "sonarr-${sanitizeName name}-inline-key" s.apiKey
            }"
          )
          cfg.sonarr;
      };

      script = ''
        set -euo pipefail

        BASE_URL="${baseUrl}"

        # Authenticate
        source ${authUtil.authScript}

        # Configure each Sonarr instance
        ${concatStringsSep "\n" (mapAttrsToList mkSonarrConfigScript cfg.sonarr)}

        # Delete servers not in configuration
        CONFIGURED_NAMES="${pkgs.writeText "sonarr-names.json" (builtins.toJSON (attrNames cfg.sonarr))}"

        EXISTING_SERVERS=$(${pkgs.curl}/bin/curl -s \
          -b "${authUtil.cookieFile}" \
          "$BASE_URL/api/v1/settings/sonarr")

        SERVERS_TO_DELETE=$(echo "$EXISTING_SERVERS" | ${pkgs.jq}/bin/jq -r \
          --slurpfile configured "$CONFIGURED_NAMES" \
          '.[] | select([.name] | inside($configured[0]) | not) | .id')

        for server_id in $SERVERS_TO_DELETE; do
          echo "Deleting Sonarr server (ID: $server_id)..."
          ${pkgs.curl}/bin/curl -sf -X DELETE \
            -b "${authUtil.cookieFile}" \
            "$BASE_URL/api/v1/settings/sonarr/$server_id" >/dev/null
        done

        echo "Sonarr configuration completed"
      '';
    };
  };
}

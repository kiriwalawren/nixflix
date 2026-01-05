{
  config,
  lib,
  pkgs,
  recyclarrConfig,
  ...
}:
with lib; let
  inherit (config) nixflix;
  cfg = nixflix.recyclarr;

  sonarrBaseUrl =
    optionalString cfg.sonarr.enable
    "http://127.0.0.1:${toString nixflix.sonarr.config.hostConfig.port}${toString nixflix.sonarr.config.hostConfig.urlBase}";

  sonarrAnimeBaseUrl =
    optionalString cfg.sonarr-anime.enable
    "http://127.0.0.1:${toString nixflix.sonarr-anime.config.hostConfig.port}${toString nixflix.sonarr-anime.config.hostConfig.urlBase}";

  radarrBaseUrl =
    optionalString cfg.radarr.enable
    "http://127.0.0.1:${toString nixflix.radarr.config.hostConfig.port}${toString nixflix.radarr.config.hostConfig.urlBase}";

  sonarrApiVersion =
    if cfg.sonarr.enable
    then nixflix.sonarr.config.apiVersion
    else "v3";

  sonarrAnimeApiVersion =
    if cfg.sonarr-anime.enable
    then nixflix.sonarr-anime.config.apiVersion
    else "v3";

  radarrApiVersion =
    if cfg.radarr.enable
    then nixflix.radarr.config.apiVersion
    else "v3";

  sonarrInstances = optionals (recyclarrConfig ? sonarr)
    (mapAttrsToList (instanceName: instanceConfig:
      let
        hasProfiles = (length instanceConfig.quality_profiles) > 0;
        matchesMain = instanceConfig.base_url == sonarrBaseUrl;
        matchesAnime = instanceConfig.base_url == sonarrAnimeBaseUrl;
      in
        optional (hasProfiles && matchesMain) {
          serviceType = "sonarr";
          inherit instanceName;
          apiVersion = sonarrApiVersion;
          baseUrl = instanceConfig.base_url;
          managedProfiles = map (p: p.name) instanceConfig.quality_profiles;
          credentialName = "sonarr-api_key";
        }
        ++ optional (hasProfiles && matchesAnime) {
          serviceType = "sonarr";
          inherit instanceName;
          apiVersion = sonarrAnimeApiVersion;
          baseUrl = instanceConfig.base_url;
          managedProfiles = map (p: p.name) instanceConfig.quality_profiles;
          credentialName = "sonarr-anime-api_key";
        }
    ) recyclarrConfig.sonarr);

  radarrInstances = optionals (recyclarrConfig ? radarr)
    (mapAttrsToList (instanceName: instanceConfig:
      let
        hasProfiles = (length instanceConfig.quality_profiles) > 0;
        matchesNixflix = instanceConfig.base_url == radarrBaseUrl;
      in
        optional (hasProfiles && matchesNixflix) {
          serviceType = "radarr";
          inherit instanceName;
          apiVersion = radarrApiVersion;
          baseUrl = instanceConfig.base_url;
          managedProfiles = map (p: p.name) instanceConfig.quality_profiles;
          credentialName = "radarr-api_key";
        }
    ) recyclarrConfig.radarr);

  instancesWithProfiles = flatten (sonarrInstances ++ radarrInstances);

  cleanupConfig = builtins.toJSON {instances = instancesWithProfiles;};

  cleanupScript = pkgs.writeShellScript "cleanup-quality-profiles.sh" ''
    set -euo pipefail

    # Read configuration
    CONFIG='${cleanupConfig}'

    # Parse instances
    INSTANCES=$(echo "$CONFIG" | ${pkgs.jq}/bin/jq -c '.instances[]')

    if [ -z "$INSTANCES" ]; then
      echo "No instances with managed quality profiles found"
      exit 0
    fi

    echo "Starting quality profile cleanup..."

    while IFS= read -r instance; do
      SERVICE_TYPE=$(echo "$instance" | ${pkgs.jq}/bin/jq -r '.serviceType')
      INSTANCE_NAME=$(echo "$instance" | ${pkgs.jq}/bin/jq -r '.instanceName')
      BASE_URL=$(echo "$instance" | ${pkgs.jq}/bin/jq -r '.baseUrl')
      API_VERSION=$(echo "$instance" | ${pkgs.jq}/bin/jq -r '.apiVersion')
      MANAGED_PROFILES=$(echo "$instance" | ${pkgs.jq}/bin/jq -c '.managedProfiles')
      CREDENTIAL_NAME=$(echo "$instance" | ${pkgs.jq}/bin/jq -r '.credentialName')

      echo "Processing $SERVICE_TYPE instance: $INSTANCE_NAME"
      echo "  Base URL: $BASE_URL"
      echo "  API Version: $API_VERSION"
      echo "  Managed profiles: $MANAGED_PROFILES"

      # Get API key from credentials
      API_KEY=$(cat /run/credentials/recyclarr-cleanup-profiles.service/$CREDENTIAL_NAME)

      # Determine media endpoint based on service type
      if [ "$SERVICE_TYPE" = "sonarr" ]; then
        MEDIA_ENDPOINT="series"
      else
        MEDIA_ENDPOINT="movie"
      fi

      # Fetch all quality profiles from the service
      ALL_PROFILES=$(${pkgs.curl}/bin/curl -s -H "X-Api-Key: $API_KEY" "$BASE_URL/api/$API_VERSION/qualityprofile")

      if [ -z "$ALL_PROFILES" ] || [ "$ALL_PROFILES" = "[]" ]; then
        echo "  No quality profiles found in $INSTANCE_NAME"
        continue
      fi

      # Find profiles to delete (those not in managed list)
      PROFILES_TO_DELETE=$(echo "$ALL_PROFILES" | ${pkgs.jq}/bin/jq -c --argjson managed "$MANAGED_PROFILES" '
        map(select(.name as $name | $managed | index($name) | not))
      ')

      PROFILE_COUNT=$(echo "$PROFILES_TO_DELETE" | ${pkgs.jq}/bin/jq 'length')

      if [ "$PROFILE_COUNT" -eq 0 ]; then
        echo "  No unmanaged profiles to delete"
        continue
      fi

      echo "  Found $PROFILE_COUNT unmanaged profile(s) to delete"

      # Get the first managed profile to use as default for reassignment
      DEFAULT_PROFILE_NAME=$(echo "$MANAGED_PROFILES" | ${pkgs.jq}/bin/jq -r '.[0]')
      DEFAULT_PROFILE_ID=$(echo "$ALL_PROFILES" | ${pkgs.jq}/bin/jq -r --arg name "$DEFAULT_PROFILE_NAME" '
        map(select(.name == $name)) | .[0].id
      ')

      if [ -z "$DEFAULT_PROFILE_ID" ] || [ "$DEFAULT_PROFILE_ID" = "null" ]; then
        echo "  ERROR: Could not find default managed profile '$DEFAULT_PROFILE_NAME'"
        continue
      fi

      echo "  Default profile for reassignment: $DEFAULT_PROFILE_NAME (ID: $DEFAULT_PROFILE_ID)"

      # Process each profile to delete
      while IFS= read -r profile; do
        PROFILE_ID=$(echo "$profile" | ${pkgs.jq}/bin/jq -r '.id')
        PROFILE_NAME=$(echo "$profile" | ${pkgs.jq}/bin/jq -r '.name')

        echo "  Processing unmanaged profile: $PROFILE_NAME (ID: $PROFILE_ID)"

        # Find all media items using this profile
        MEDIA_ITEMS=$(${pkgs.curl}/bin/curl -s -H "X-Api-Key: $API_KEY" "$BASE_URL/api/$API_VERSION/$MEDIA_ENDPOINT")
        ITEMS_WITH_PROFILE=$(echo "$MEDIA_ITEMS" | ${pkgs.jq}/bin/jq -c --arg profileId "$PROFILE_ID" '
          map(select(.qualityProfileId == ($profileId | tonumber)))
        ')

        ITEM_COUNT=$(echo "$ITEMS_WITH_PROFILE" | ${pkgs.jq}/bin/jq 'length')

        if [ "$ITEM_COUNT" -gt 0 ]; then
          echo "    Reassigning $ITEM_COUNT item(s) to default profile..."

          while IFS= read -r item; do
            ITEM_ID=$(echo "$item" | ${pkgs.jq}/bin/jq -r '.id')
            ITEM_TITLE=$(echo "$item" | ${pkgs.jq}/bin/jq -r '.title')

            # Update the item to use the default profile
            UPDATED_ITEM=$(echo "$item" | ${pkgs.jq}/bin/jq --arg profileId "$DEFAULT_PROFILE_ID" '
              .qualityProfileId = ($profileId | tonumber)
            ')

            ${pkgs.curl}/bin/curl -s -X PUT \
              -H "X-Api-Key: $API_KEY" \
              -H "Content-Type: application/json" \
              -d "$UPDATED_ITEM" \
              "$BASE_URL/api/$API_VERSION/$MEDIA_ENDPOINT/$ITEM_ID" > /dev/null

            echo "      Reassigned: $ITEM_TITLE"
          done < <(echo "$ITEMS_WITH_PROFILE" | ${pkgs.jq}/bin/jq -c '.[]')
        fi

        # Delete the quality profile
        DELETE_RESPONSE=$(${pkgs.curl}/bin/curl -s -w "\n%{http_code}" -X DELETE \
          -H "X-Api-Key: $API_KEY" \
          "$BASE_URL/api/$API_VERSION/qualityprofile/$PROFILE_ID")

        HTTP_CODE=$(echo "$DELETE_RESPONSE" | tail -n1)

        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "204" ]; then
          echo "    ✓ Deleted profile: $PROFILE_NAME"
        else
          RESPONSE_BODY=$(echo "$DELETE_RESPONSE" | head -n-1)
          echo "    ✗ Failed to delete profile: $PROFILE_NAME (HTTP $HTTP_CODE)"
          echo "      Response: $RESPONSE_BODY"
        fi

      done < <(echo "$PROFILES_TO_DELETE" | ${pkgs.jq}/bin/jq -c '.[]')

    done < <(echo "$CONFIG" | ${pkgs.jq}/bin/jq -c '.instances[]')

    echo "Quality profile cleanup completed"
  '';
in {
  recyclarr-cleanup-profiles = mkIf cfg.cleanupUnmanagedProfiles {
    description = "Cleanup unmanaged quality profiles from Sonarr/Radarr";
    after = ["recyclarr.service"];
    wants = ["recyclarr.service"];
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = cleanupScript;
      User = cfg.user;
      Group = cfg.group;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateDevices = true;

      LoadCredential =
        optional cfg.radarr.enable "radarr-api_key:${nixflix.radarr.config.apiKeyPath}"
        ++ optional cfg.sonarr.enable "sonarr-api_key:${nixflix.sonarr.config.apiKeyPath}"
        ++ optional cfg.sonarr-anime.enable "sonarr-anime-api_key:${nixflix.sonarr-anime.config.apiKeyPath}";
    };
  };
}

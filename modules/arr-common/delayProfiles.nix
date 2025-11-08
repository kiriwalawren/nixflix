{
  lib,
  pkgs,
  serviceName,
}:
with lib; let
  capitalizedName = lib.toUpper (builtins.substring 0 1 serviceName) + builtins.substring 1 (-1) serviceName;

  defaultDelayProfile = {
    enableUsenet = true;
    enableTorrent = true;
    preferredProtocol = "usenet";
    usenetDelay = 0;
    torrentDelay = 0;
    bypassIfHighestQuality = true;
    bypassIfAboveCustomFormatScore = false;
    minimumCustomFormatScore = 0;
    order = 2147483647;
    tags = [];
    id = 1;
  };
in {
  options = mkOption {
    type = types.listOf (types.submodule {
      options = {
        id = mkOption {
          type = types.int;
          description = "Unique identifier for the delay profile";
        };
        enableUsenet = mkOption {
          type = types.bool;
          default = true;
          description = "Enable Usenet protocol for this profile";
        };
        enableTorrent = mkOption {
          type = types.bool;
          default = true;
          description = "Enable Torrent protocol for this profile";
        };
        preferredProtocol = mkOption {
          type = types.enum ["usenet" "torrent"];
          default = "usenet";
          description = "Preferred download protocol when both are available";
        };
        usenetDelay = mkOption {
          type = types.int;
          default = 0;
          description = "Delay in minutes before grabbing a Usenet release";
        };
        torrentDelay = mkOption {
          type = types.int;
          default = 360;
          description = "Delay in minutes before grabbing a Torrent release";
        };
        bypassIfHighestQuality = mkOption {
          type = types.bool;
          default = true;
          description = "Bypass delay if release is the highest quality available";
        };
        bypassIfAboveCustomFormatScore = mkOption {
          type = types.bool;
          default = false;
          description = "Bypass delay if custom format score is above minimum";
        };
        minimumCustomFormatScore = mkOption {
          type = types.int;
          default = 0;
          description = "Minimum custom format score to bypass delay";
        };
        order = mkOption {
          type = types.int;
          default = 50;
          description = "Order/priority of this delay profile (lower values = higher priority)";
        };
        tags = mkOption {
          type = types.listOf types.int;
          default = [];
          description = "List of tag IDs this delay profile applies to (empty = applies to all)";
        };
      };
    });
    default = [defaultDelayProfile];
    defaultText = literalExpression ''
      [
        {
          enableUsenet = true;
          enableTorrent = true;
          preferredProtocol = "usenet";
          usenetDelay = 0;
          torrentDelay = 0;
          bypassIfHighestQuality = true;
          bypassIfAboveCustomFormatScore = false;
          minimumCustomFormatScore = 0;
          order = 2147483647;
          tags = [];
          id = 1;
        };
      ]
    '';
    description = ''
      List of delay profiles to configure via the API /delayprofile endpoint.

      Profiles are created/updated in id order. If no profile with id=1 is provided,
      a default profile will be added automatically.
    '';
  };

  mkService = serviceConfig: {
    description = "Configure ${serviceName} delay profiles via API";
    after = ["${serviceName}-config.service"];
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = let
      # Auto-merge default profile (id=1) if not present in user config
      userProfileIds = map (p: p.id) serviceConfig.delayProfiles;
      hasDefaultProfile = elem 1 userProfileIds;
      mergedProfiles =
        if hasDefaultProfile
        then serviceConfig.delayProfiles
        else [defaultDelayProfile] ++ serviceConfig.delayProfiles;

      # Sort profiles by id to ensure proper creation order
      sortedProfiles = sort (a: b: a.id < b.id) mergedProfiles;
    in ''
      set -eu

      # Read API key secret
      API_KEY=$(cat ${serviceConfig.apiKeyPath})

      BASE_URL="http://127.0.0.1:${builtins.toString serviceConfig.hostConfig.port}${serviceConfig.hostConfig.urlBase}/api/${serviceConfig.apiVersion}"

      # Fetch existing delay profiles
      echo "Fetching existing delay profiles..."
      DELAY_PROFILES=$(${pkgs.curl}/bin/curl -sSf -H "X-Api-Key: $API_KEY" "$BASE_URL/delayprofile" 2>/dev/null)

      # Build list of configured profile IDs
      CONFIGURED_IDS=$(cat <<'EOF'
      ${builtins.toJSON (map (p: p.id) sortedProfiles)}
      EOF
      )

      # Delete delay profiles that are not in the configuration
      echo "Removing delay profiles not in configuration..."
      echo "$DELAY_PROFILES" | ${pkgs.jq}/bin/jq -r '.[] | @json' | while IFS= read -r profile; do
        PROFILE_ID=$(echo "$profile" | ${pkgs.jq}/bin/jq -r '.id')

        if ! echo "$CONFIGURED_IDS" | ${pkgs.jq}/bin/jq -e --argjson id "$PROFILE_ID" 'index($id)' >/dev/null 2>&1; then
          echo "Deleting delay profile not in config (ID: $PROFILE_ID)"
          ${pkgs.curl}/bin/curl -sSf -X DELETE \
            -H "X-Api-Key: $API_KEY" \
            "$BASE_URL/delayprofile/$PROFILE_ID" >/dev/null 2>&1 || echo "Warning: Failed to delete delay profile $PROFILE_ID (may be in use)"
        fi
      done

      ${concatMapStringsSep "\n" (profileConfig: let
          profileJson = builtins.toJSON profileConfig;
          profileId = toString profileConfig.id;
        in ''
          echo "Processing delay profile (ID: ${profileId})..."

          EXISTING_PROFILE=$(echo "$DELAY_PROFILES" | ${pkgs.jq}/bin/jq -r '.[] | select(.id == ${profileId}) | @json' || echo "")

          if [ -n "$EXISTING_PROFILE" ]; then
            echo "Delay profile ${profileId} already exists, updating..."
            ${pkgs.curl}/bin/curl -sSf -X PUT \
              -H "X-Api-Key: $API_KEY" \
              -H "Content-Type: application/json" \
              -d '${profileJson}' \
              "$BASE_URL/delayprofile/${profileId}" > /dev/null
            echo "Delay profile ${profileId} updated"
          else
            echo "Delay profile ${profileId} does not exist, creating..."
            ${pkgs.curl}/bin/curl -sSf -X POST \
              -H "X-Api-Key: $API_KEY" \
              -H "Content-Type: application/json" \
              -d '${profileJson}' \
              "$BASE_URL/delayprofile" > /dev/null
            echo "Delay profile ${profileId} created"
          fi
        '')
        sortedProfiles}

      echo "${capitalizedName} delay profiles configuration complete"
    '';
  };
}

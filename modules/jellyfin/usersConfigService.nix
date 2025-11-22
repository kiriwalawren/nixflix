{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  inherit (config) nixflix;
  cfg = config.nixflix.jellyfin;

  util = import ./util.nix {inherit lib;};
  authUtil = import ./authUtil.nix {inherit lib pkgs cfg;};

  transformSyncPlayAccess = hasAccess:
    if hasAccess
    then "CreateAndJoinGroups"
    else "None";

  buildUserPayload = userName: userCfg: {
    name = userName;
    inherit (userCfg) enableAutoLogin;
    configuration = util.recursiveTransform userCfg.preferences;
    policy = util.recursiveTransform (userCfg.policy
      // {
        syncPlayAccess = transformSyncPlayAccess userCfg.policy.syncPlayAccess;
      });
  };

  userConfigFiles =
    mapAttrs (
      userName: userCfg:
        pkgs.writeText "jellyfin-user-${userName}.json"
        (builtins.toJSON (util.recursiveTransform (buildUserPayload userName userCfg)))
    )
    cfg.users;
in {
  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.services.jellyfin-users-config = {
      description = "Configure Jellyfin Users via API";
      after = ["jellyfin-setup-wizard.service"];
      requires = ["jellyfin-setup-wizard.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -eu

        BASE_URL="http://127.0.0.1:${toString cfg.network.internalHttpPort}${cfg.network.baseUrl}"

        echo "Configuring Jellyfin users..."

        source ${authUtil.authScript}

        echo "Fetching users from $BASE_URL/Users..."
        USERS_RESPONSE=$(${pkgs.curl}/bin/curl -s -w "\n%{http_code}" -H "Authorization: MediaBrowser Client=\"nixflix\", Device=\"NixOS\", DeviceId=\"nixflix-users-config\", Version=\"1.0.0\", Token=\"$ACCESS_TOKEN\"" "$BASE_URL/Users")

        USERS_HTTP_CODE=$(echo "$USERS_RESPONSE" | tail -n1)
        USERS_JSON=$(echo "$USERS_RESPONSE" | sed '$d')

        echo "Users endpoint response (HTTP $USERS_HTTP_CODE): $USERS_JSON"

        if [ "$USERS_HTTP_CODE" -lt 200 ] || [ "$USERS_HTTP_CODE" -ge 300 ]; then
          echo "Failed to fetch users from Jellyfin API (HTTP $USERS_HTTP_CODE)" >&2
          exit 1
        fi

        ${concatStringsSep "\n" (mapAttrsToList (userName: userCfg: ''
            echo "Processing user: ${userName}"

            USER_ID=$(echo "$USERS_JSON" | ${pkgs.jq}/bin/jq -r '.[] | select(.Name == "${userName}") | .Id' || echo "")
            echo "Found USER_ID for ${userName}: $USER_ID"
            IS_NEW_USER=false

            if [ -z "$USER_ID" ]; then
              echo "Creating new user: ${userName}"
              IS_NEW_USER=true

              ${
              if userCfg.passwordFile != null
              then ''PASSWORD=$(${pkgs.coreutils}/bin/cat ${userCfg.passwordFile})''
              else ''PASSWORD=""''
            }

              RESPONSE=$(${pkgs.curl}/bin/curl -X POST \
                -H "Authorization: MediaBrowser Client=\"nixflix\", Device=\"NixOS\", DeviceId=\"nixflix-users-config\", Version=\"1.0.0\", Token=\"$ACCESS_TOKEN\"" \
                -H "Content-Type: application/json" \
                -d "{\"Name\": \"${userName}\", \"Password\": \"$PASSWORD\"}" \
                -w "\n%{http_code}" \
                "$BASE_URL/Users/New")

              HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
              BODY=$(echo "$RESPONSE" | sed '$d')

              echo "Create user response (HTTP $HTTP_CODE): $BODY"

              if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
                echo "Failed to create user ${userName} (HTTP $HTTP_CODE)" >&2
                exit 1
              fi

              USERS_JSON=$(${pkgs.curl}/bin/curl -s -H "Authorization: MediaBrowser Client=\"nixflix\", Device=\"NixOS\", DeviceId=\"nixflix-users-config\", Version=\"1.0.0\", Token=\"$ACCESS_TOKEN\"" "$BASE_URL/Users")
              USER_ID=$(echo "$USERS_JSON" | ${pkgs.jq}/bin/jq -r '.[] | select(.Name == "${userName}") | .Id')
            fi

            SHOULD_UPDATE=false
            if [ "$IS_NEW_USER" = "true" ]; then
              SHOULD_UPDATE=true
            elif [ "${boolToString userCfg.mutable}" = "false" ]; then
              SHOULD_UPDATE=true
            fi

            if [ "$SHOULD_UPDATE" = "true" ]; then
              echo "Updating user configuration for: ${userName}"

              UPDATE_RESPONSE=$(${pkgs.curl}/bin/curl -X POST \
                -H "Authorization: MediaBrowser Client=\"nixflix\", Device=\"NixOS\", DeviceId=\"nixflix-users-config\", Version=\"1.0.0\", Token=\"$ACCESS_TOKEN\"" \
                -H "Content-Type: application/json" \
                -d @${userConfigFiles.${userName}} \
                -w "\n%{http_code}" \
                "$BASE_URL/Users?userId=$USER_ID")

              UPDATE_HTTP_CODE=$(echo "$UPDATE_RESPONSE" | tail -n1)
              UPDATE_BODY=$(echo "$UPDATE_RESPONSE" | sed '$d')

              echo "Update user response (HTTP $UPDATE_HTTP_CODE): $UPDATE_BODY"

              if [ "$UPDATE_HTTP_CODE" -lt 200 ] || [ "$UPDATE_HTTP_CODE" -ge 300 ]; then
                echo "Failed to update user ${userName} (HTTP $UPDATE_HTTP_CODE)" >&2
                exit 1
              fi
            else
              echo "Skipping user ${userName} (mutable=true and not a new user)"
            fi
          '')
          cfg.users)}

        echo "User configuration completed successfully"
      '';
    };
  };
}

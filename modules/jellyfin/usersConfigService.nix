{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  secrets = import ../lib/secrets {inherit lib;};
  inherit (config) nixflix;
  cfg = config.nixflix.jellyfin;

  util = import ./util.nix {inherit lib;};
  authUtil = import ./authUtil.nix {inherit lib pkgs cfg;};

  buildUserPayload = userName: userCfg: {
    name = userName;
    inherit (userCfg) enableAutoLogin;
    configuration = util.recursiveTransform userCfg.configuration;
    policy = util.recursiveTransform userCfg.policy;
  };

  userConfigFiles =
    mapAttrs (
      userName: userCfg:
        pkgs.writeText "jellyfin-user-${userName}.json"
        (builtins.toJSON (util.recursiveTransform (buildUserPayload userName userCfg)))
    )
    cfg.users;

  baseUrl =
    if cfg.network.baseUrl == ""
    then "http://127.0.0.1:${toString cfg.network.internalHttpPort}"
    else "http://127.0.0.1:${toString cfg.network.internalHttpPort}/${cfg.network.baseUrl}";
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

        BASE_URL="${baseUrl}"

        echo "Configuring Jellyfin users..."

        source ${authUtil.authScript}

        echo "Fetching users from $BASE_URL/Users..."
        USERS_RESPONSE=$(${pkgs.curl}/bin/curl -s -w "\n%{http_code}" -H "$AUTH_HEADER" "$BASE_URL/Users")

        USERS_HTTP_CODE=$(echo "$USERS_RESPONSE" | tail -n1)
        USERS_JSON=$(echo "$USERS_RESPONSE" | sed '$d')

        echo "Users endpoint response (HTTP $USERS_HTTP_CODE): $USERS_JSON"

        if [ "$USERS_HTTP_CODE" -lt 200 ] || [ "$USERS_HTTP_CODE" -ge 300 ]; then
          echo "Failed to fetch users from Jellyfin API (HTTP $USERS_HTTP_CODE)" >&2
          exit 1
        fi

        ${concatStringsSep "\n" (mapAttrsToList (userName: userCfg: ''
            echo "=========================================="
            echo "Processing user: ${userName}"
            echo "=========================================="

            USER_ID=$(echo "$USERS_JSON" | ${pkgs.jq}/bin/jq -r '.[] | select(.Name == "${userName}") | .Id' || echo "")
            echo "Found USER_ID for ${userName}: $USER_ID"
            IS_NEW_USER=false

            if [ -z "$USER_ID" ]; then
              echo "Creating new user: ${userName}"
              IS_NEW_USER=true

            ${
              if userCfg.password != null
              then secrets.toShellValue "PASSWORD" userCfg.password
              else ''PASSWORD=""''
            }

              RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST \
                -H "$AUTH_HEADER" \
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

              USERS_JSON=$(${pkgs.curl}/bin/curl -s -H "$AUTH_HEADER" "$BASE_URL/Users")
              USER_ID=$(echo "$USERS_JSON" | ${pkgs.jq}/bin/jq -r '.[] | select(.Name == "${userName}") | .Id')
            fi

            echo "Current user settings from server:"
            echo "$USERS_JSON" | ${pkgs.jq}/bin/jq ".[] | select(.Name == \"${userName}\")"

            echo ""
            echo "Configured payload to send:"
            ${pkgs.coreutils}/bin/cat ${userConfigFiles.${userName}} | ${pkgs.jq}/bin/jq .

            echo ""
            echo "mutable setting: ${boolToString userCfg.mutable}"
            echo "IS_NEW_USER: $IS_NEW_USER"

            SHOULD_UPDATE=false
            if [ "$IS_NEW_USER" = "true" ]; then
              SHOULD_UPDATE=true
              echo "Update decision: YES (new user)"
            elif [ "${boolToString userCfg.mutable}" = "false" ]; then
              SHOULD_UPDATE=true
              echo "Update decision: YES (mutable=false)"
            else
              echo "Update decision: NO (mutable=true and existing user)"
            fi

            if [ "$SHOULD_UPDATE" = "true" ]; then
              echo ""
              echo "Sending configuration update request to: $BASE_URL/Users/$USER_ID"

              # Update user configuration and basic settings
              UPDATE_RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST \
                -H "$AUTH_HEADER" \
                -H "Content-Type: application/json" \
                -d @${userConfigFiles.${userName}} \
                -w "\n%{http_code}" \
                "$BASE_URL/Users/$USER_ID")

              UPDATE_HTTP_CODE=$(echo "$UPDATE_RESPONSE" | tail -n1)
              UPDATE_BODY=$(echo "$UPDATE_RESPONSE" | sed '$d')

              echo "Update user configuration response (HTTP $UPDATE_HTTP_CODE):"
              echo "$UPDATE_BODY" | ${pkgs.jq}/bin/jq . || echo "$UPDATE_BODY"

              if [ "$UPDATE_HTTP_CODE" -lt 200 ] || [ "$UPDATE_HTTP_CODE" -ge 300 ]; then
                echo "Failed to update user configuration for ${userName} (HTTP $UPDATE_HTTP_CODE)" >&2
                exit 1
              fi

              echo ""
              echo "Sending policy update request to: $BASE_URL/Users/$USER_ID/Policy"

              # Fetch current policy from server
              CURRENT_POLICY=$(${pkgs.curl}/bin/curl -s -H "$AUTH_HEADER" "$BASE_URL/Users/$USER_ID")

              # Get our desired policy settings
              DESIRED_POLICY=$(${pkgs.coreutils}/bin/cat ${userConfigFiles.${userName}} | ${pkgs.jq}/bin/jq '.Policy')

              # Merge: start with current policy, overlay our desired changes
              POLICY_JSON=$(echo "$CURRENT_POLICY" | ${pkgs.jq}/bin/jq --argjson desired "$DESIRED_POLICY" '.Policy * $desired')

              POLICY_RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST \
                -H "$AUTH_HEADER" \
                -H "Content-Type: application/json" \
                -d "$POLICY_JSON" \
                -w "\n%{http_code}" \
                "$BASE_URL/Users/$USER_ID/Policy")

              POLICY_HTTP_CODE=$(echo "$POLICY_RESPONSE" | tail -n1)
              POLICY_BODY=$(echo "$POLICY_RESPONSE" | sed '$d')

              echo "Update user policy response (HTTP $POLICY_HTTP_CODE):"
              echo "$POLICY_BODY" | ${pkgs.jq}/bin/jq . || echo "$POLICY_BODY"

              if [ "$POLICY_HTTP_CODE" -lt 200 ] || [ "$POLICY_HTTP_CODE" -ge 300 ]; then
                echo "Failed to update user policy for ${userName} (HTTP $POLICY_HTTP_CODE)" >&2
                exit 1
              fi

              echo ""
              echo "Verifying update - fetching user again:"
              VERIFY_RESPONSE=$(${pkgs.curl}/bin/curl -s -H "$AUTH_HEADER" "$BASE_URL/Users/$USER_ID")
              echo "$VERIFY_RESPONSE" | ${pkgs.jq}/bin/jq .
            else
              echo "Skipping user ${userName} - no update needed"
            fi
            echo ""
          '')
          cfg.users)}

        echo "User configuration completed successfully"
      '';
    };
  };
}

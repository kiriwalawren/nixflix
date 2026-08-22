{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  getFirstAdmin = import ../../lib/getFirstAdmin.nix { inherit lib; };
  inherit (config) nixflix;
  cfg = nixflix.navidrome;

  firstAdminUser =
    (getFirstAdmin {
      inherit (cfg) users;
      isAdmin = user: user.isAdmin;
    }).user;

  jqLoginSecrets = secrets.mkJqSecretArgs { inherit (firstAdminUser) password; };

  baseUrl = "http://${cfg.connectionAddress}:${toString cfg.settings.Port}";
in
{
  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.services.navidrome-users-config = {
      description = "Configure Navidrome Users via API";
      after = [ "navidrome-create-admin.service" ];
      requires = [ "navidrome-create-admin.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -eu

        BASE_URL="${baseUrl}"

        echo "Configuring Navidrome users..."

        HEADERS_FILE=$(${pkgs.coreutils}/bin/mktemp)
        trap 'rm -f "$HEADERS_FILE"' EXIT

        nd_request() {
          local method="$1"
          local path="$2"
          local data="''${3:-}"
          local curl_args=(
            -s
            -D "$HEADERS_FILE"
            -X "$method"
            -H "Content-Type: application/json"
            -H "x-nd-authorization: Bearer $TOKEN"
            -w "\n%{http_code}"
          )
          if [ -n "$data" ]; then
            curl_args+=(-d "$data")
          fi

          local response
          response=$(${pkgs.curl}/bin/curl "''${curl_args[@]}" "$BASE_URL$path")
          ND_HTTP_CODE=$(echo "$response" | tail -n1)
          ND_BODY=$(echo "$response" | sed '$d')

          local new_token
          new_token=$(${pkgs.gnugrep}/bin/grep -i '^x-nd-authorization:' "$HEADERS_FILE" | tail -n1 | cut -d' ' -f2- | tr -d '\r\n')
          if [ -n "$new_token" ]; then
            TOKEN="$new_token"
          fi
        }

        echo "Logging in as ${firstAdminUser.userName}..."
        LOGIN_PAYLOAD=$(${pkgs.jq}/bin/jq -n \
          ${jqLoginSecrets.flagsString} \
          --arg username ${escapeShellArg firstAdminUser.userName} \
          '{username: $username, password: ${jqLoginSecrets.refs.password}}')

        LOGIN_RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST \
          -H "Content-Type: application/json" \
          -d "$LOGIN_PAYLOAD" \
          -w "\n%{http_code}" \
          "$BASE_URL/auth/login")

        LOGIN_HTTP_CODE=$(echo "$LOGIN_RESPONSE" | tail -n1)
        LOGIN_BODY=$(echo "$LOGIN_RESPONSE" | sed '$d')

        if [ "$LOGIN_HTTP_CODE" -lt 200 ] || [ "$LOGIN_HTTP_CODE" -ge 300 ]; then
          echo "Failed to log in as ${firstAdminUser.userName} (HTTP $LOGIN_HTTP_CODE): $LOGIN_BODY" >&2
          exit 1
        fi

        TOKEN=$(echo "$LOGIN_BODY" | ${pkgs.jq}/bin/jq -r '.token')

        echo "Fetching existing Navidrome users..."
        nd_request GET "/api/user?_end=200&_order=ASC&_sort=userName&_start=0"

        if [ "$ND_HTTP_CODE" -lt 200 ] || [ "$ND_HTTP_CODE" -ge 300 ]; then
          echo "Failed to fetch users from Navidrome API (HTTP $ND_HTTP_CODE): $ND_BODY" >&2
          exit 1
        fi

        USERS_JSON="$ND_BODY"

        ${concatStringsSep "\n" (
          mapAttrsToList (
            userName: userCfg:
            let
              jqUserSecrets = secrets.mkJqSecretArgs { inherit (userCfg) password; };
              userEmail = if userCfg.email == null then "" else userCfg.email;
              resolvedUserName = if userCfg.userName != null then userCfg.userName else userName;
            in
            ''
              echo "=========================================="
              echo "Processing user: ${userName}"
              echo "=========================================="

              EXISTING_USER=$(echo "$USERS_JSON" | ${pkgs.jq}/bin/jq -c --arg name ${escapeShellArg resolvedUserName} '.[] | select(.userName | ascii_downcase == ($name | ascii_downcase))' || echo "")
              IS_NEW_USER=false

              if [ -z "$EXISTING_USER" ]; then
                echo "Creating new user: ${resolvedUserName}"
                IS_NEW_USER=true

                CREATE_PAYLOAD=$(${pkgs.jq}/bin/jq -n \
                  ${jqUserSecrets.flagsString} \
                  --arg userName ${escapeShellArg resolvedUserName} \
                  --arg name ${escapeShellArg userName} \
                  --arg email ${escapeShellArg userEmail} \
                  '{userName: $userName, name: $name, email: $email, isAdmin: ${boolToString userCfg.isAdmin}, password: ${jqUserSecrets.refs.password}}')

                nd_request POST "/api/user" "$CREATE_PAYLOAD"

                if [ "$ND_HTTP_CODE" -lt 200 ] || [ "$ND_HTTP_CODE" -ge 300 ]; then
                  echo "Failed to create user ${resolvedUserName} (HTTP $ND_HTTP_CODE): $ND_BODY" >&2
                  exit 1
                fi

                echo "Created user ${resolvedUserName}"

                nd_request GET "/api/user?_end=200&_order=ASC&_sort=userName&_start=0"

                if [ "$ND_HTTP_CODE" -lt 200 ] || [ "$ND_HTTP_CODE" -ge 300 ]; then
                  echo "Failed to re-fetch users from Navidrome API (HTTP $ND_HTTP_CODE): $ND_BODY" >&2
                  exit 1
                fi

                USERS_JSON="$ND_BODY"
                EXISTING_USER=$(echo "$USERS_JSON" | ${pkgs.jq}/bin/jq -c --arg name ${escapeShellArg resolvedUserName} '.[] | select(.userName | ascii_downcase == ($name | ascii_downcase))')
              fi

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
                USER_ID=$(echo "$EXISTING_USER" | ${pkgs.jq}/bin/jq -r '.id')
                echo "Updating user ${resolvedUserName} (id: $USER_ID)"

                UPDATE_PAYLOAD=$(echo "$EXISTING_USER" | ${pkgs.jq}/bin/jq \
                  --arg userName ${escapeShellArg resolvedUserName} \
                  --arg name ${escapeShellArg userName} \
                  --arg email ${escapeShellArg userEmail} \
                  '. + {userName: $userName, name: $name, email: $email, isAdmin: ${boolToString userCfg.isAdmin}}')

                nd_request PUT "/api/user/$USER_ID" "$UPDATE_PAYLOAD"

                if [ "$ND_HTTP_CODE" -lt 200 ] || [ "$ND_HTTP_CODE" -ge 300 ]; then
                  echo "Failed to update user ${resolvedUserName} (HTTP $ND_HTTP_CODE): $ND_BODY" >&2
                  exit 1
                fi

                echo "Updated user ${resolvedUserName}"
              else
                echo "Skipping user ${resolvedUserName} - no update needed"
              fi
              echo ""
            ''
          ) cfg.users
        )}

        echo "Navidrome user configuration completed successfully"
      '';
    };
  };
}

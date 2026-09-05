{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  secrets = import ../../../lib/secrets { inherit lib; };
  getFirstAdmin = import ../../../lib/getFirstAdmin.nix { inherit lib; };
  inherit (config) nixflix;
  cfg = nixflix.droppedneedle;

  firstAdmin = getFirstAdmin {
    users = cfg.settings.users;
    isAdmin = user: user.role == "admin";
  };
  firstAdminUser = firstAdmin.user;
  firstAdminUserName = firstAdminUser.userName;

  jqLoginSecrets = secrets.mkJqSecretArgs { inherit (firstAdminUser) password; };

  baseUrl = "http://${cfg.connectionAddress}:${toString cfg.port}";
  apiUrl = "${baseUrl}/api/v1";
in
{
  imports = [ ./options.nix ];

  config = mkIf (nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = lib.any (user: user.role == "admin") (lib.attrValues cfg.settings.users);
        message = "At least one DroppedNeedle user must have role = \"admin\".";
      }
    ];

    systemd.services.droppedneedle-users-config = {
      description = "Configure DroppedNeedle Users via API";
      after = [ "droppedneedle-create-admin.service" ];
      requires = [ "droppedneedle-create-admin.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -eu

        API_URL="${apiUrl}"

        echo "Configuring DroppedNeedle users..."

        dn_request() {
          local method="$1"
          local path="$2"
          local data="''${3:-}"
          local curl_args=(
            -s
            -X "$method"
            -H "Content-Type: application/json"
            -H "Authorization: Bearer $TOKEN"
            -w "\n%{http_code}"
          )
          if [ -n "$data" ]; then
            curl_args+=(-d "$data")
          fi

          local response
          response=$(${pkgs.curl}/bin/curl "''${curl_args[@]}" "$API_URL$path")
          DN_HTTP_CODE=$(echo "$response" | tail -n1)
          DN_BODY=$(echo "$response" | sed '$d')
        }

        echo "Logging in as ${firstAdminUserName}..."
        LOGIN_PAYLOAD=$(${pkgs.jq}/bin/jq -n \
          ${jqLoginSecrets.flagsString} \
          --arg username ${escapeShellArg firstAdminUserName} \
          '{username: $username, password: ${jqLoginSecrets.refs.password}}')

        LOGIN_RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST \
          -H "Content-Type: application/json" \
          -d "$LOGIN_PAYLOAD" \
          -w "\n%{http_code}" \
          "$API_URL/auth/login")

        LOGIN_HTTP_CODE=$(echo "$LOGIN_RESPONSE" | tail -n1)
        LOGIN_BODY=$(echo "$LOGIN_RESPONSE" | sed '$d')

        if [ "$LOGIN_HTTP_CODE" -lt 200 ] || [ "$LOGIN_HTTP_CODE" -ge 300 ]; then
          echo "Failed to log in as ${firstAdminUserName} (HTTP $LOGIN_HTTP_CODE): $LOGIN_BODY" >&2
          exit 1
        fi

        TOKEN=$(echo "$LOGIN_BODY" | ${pkgs.jq}/bin/jq -r '.token')

        echo "Fetching existing DroppedNeedle users..."
        dn_request GET "/auth/admin/users?limit=500&offset=0"

        if [ "$DN_HTTP_CODE" -lt 200 ] || [ "$DN_HTTP_CODE" -ge 300 ]; then
          echo "Failed to fetch users from DroppedNeedle API (HTTP $DN_HTTP_CODE): $DN_BODY" >&2
          exit 1
        fi

        USERS_JSON=$(echo "$DN_BODY" | ${pkgs.jq}/bin/jq -c '.users')

        ${concatStringsSep "\n" (
          mapAttrsToList (
            userKey: userCfg:
            let
              jqUserSecrets = secrets.mkJqSecretArgs { inherit (userCfg) password; };
              userEmail = if userCfg.email == null then "" else userCfg.email;
              resolvedUserName = userCfg.userName;
              quotaPayload = builtins.toJSON {
                request_quota_count = userCfg.quota.requestCount;
                request_quota_days = userCfg.quota.requestDays;
                storage_quota_gb = userCfg.quota.storageGb;
              };
            in
            ''
              echo "=========================================="
              echo "Processing user: ${userKey}"
              echo "=========================================="

              EXISTING_USER=$(echo "$USERS_JSON" | ${pkgs.jq}/bin/jq -c --arg name ${escapeShellArg resolvedUserName} '.[] | select((.username // "") | ascii_downcase == ($name | ascii_downcase))' || echo "")
              IS_NEW_USER=false

              if [ -z "$EXISTING_USER" ]; then
                echo "Creating new user: ${resolvedUserName}"
                IS_NEW_USER=true

                CREATE_PAYLOAD=$(${pkgs.jq}/bin/jq -n \
                  ${jqUserSecrets.flagsString} \
                  --arg displayName ${escapeShellArg userKey} \
                  --arg username ${escapeShellArg resolvedUserName} \
                  --arg email ${escapeShellArg userEmail} \
                  '{display_name: $displayName, username: $username, email: $email, role: "${userCfg.role}", password: ${jqUserSecrets.refs.password}}')

                dn_request POST "/auth/admin/users" "$CREATE_PAYLOAD"

                if [ "$DN_HTTP_CODE" = "409" ]; then
                  echo "User ${resolvedUserName} may already exist, re-checking..."
                  dn_request GET "/auth/admin/users?limit=500&offset=0"

                  if [ "$DN_HTTP_CODE" -lt 200 ] || [ "$DN_HTTP_CODE" -ge 300 ]; then
                    echo "Failed to re-fetch users from DroppedNeedle API (HTTP $DN_HTTP_CODE): $DN_BODY" >&2
                    exit 1
                  fi

                  USERS_JSON=$(echo "$DN_BODY" | ${pkgs.jq}/bin/jq -c '.users')
                  EXISTING_USER=$(echo "$USERS_JSON" | ${pkgs.jq}/bin/jq -c --arg name ${escapeShellArg resolvedUserName} '.[] | select((.username // "") | ascii_downcase == ($name | ascii_downcase))' || echo "")

                  if [ -z "$EXISTING_USER" ]; then
                    echo "Failed to create user ${resolvedUserName}: username or email conflicts with another account" >&2
                    exit 1
                  fi

                  IS_NEW_USER=false
                  echo "User ${resolvedUserName} already existed, skipping creation"
                elif [ "$DN_HTTP_CODE" -lt 200 ] || [ "$DN_HTTP_CODE" -ge 300 ]; then
                  echo "Failed to create user ${resolvedUserName} (HTTP $DN_HTTP_CODE): $DN_BODY" >&2
                  exit 1
                else
                  echo "Created user ${resolvedUserName}"
                  EXISTING_USER="$DN_BODY"
                fi
              fi

              USER_ID=$(echo "$EXISTING_USER" | ${pkgs.jq}/bin/jq -r '.id')

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
                CURRENT_ROLE=$(echo "$EXISTING_USER" | ${pkgs.jq}/bin/jq -r '.role')

                if [ "$CURRENT_ROLE" != "${userCfg.role}" ]; then
                  echo "Setting role for ${resolvedUserName}: $CURRENT_ROLE -> ${userCfg.role}"
                  dn_request PATCH "/auth/admin/users/$USER_ID/role" '{"role": "${userCfg.role}"}'

                  if [ "$DN_HTTP_CODE" -lt 200 ] || [ "$DN_HTTP_CODE" -ge 300 ]; then
                    echo "Failed to set role for ${resolvedUserName} (HTTP $DN_HTTP_CODE): $DN_BODY" >&2
                    exit 1
                  fi
                else
                  echo "Role for ${resolvedUserName} already ${userCfg.role}"
                fi

                echo "Setting quota for ${resolvedUserName}"
                dn_request PUT "/auth/admin/users/$USER_ID/quota" ${escapeShellArg quotaPayload}

                if [ "$DN_HTTP_CODE" -lt 200 ] || [ "$DN_HTTP_CODE" -ge 300 ]; then
                  echo "Failed to set quota for ${resolvedUserName} (HTTP $DN_HTTP_CODE): $DN_BODY" >&2
                  exit 1
                fi
              else
                echo "Skipping user ${resolvedUserName} - no update needed"
              fi
              echo ""
            ''
          ) cfg.settings.users
        )}

        echo "DroppedNeedle user configuration completed successfully"
      '';
    };
  };
}

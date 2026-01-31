{
  lib,
  pkgs,
  cfg,
  jellyfinCfg,
}:
with lib; let
  secrets = import ../lib/secrets {inherit lib;};
  adminUsers = filterAttrs (_: user: user.policy.isAdministrator) jellyfinCfg.users;
  sortedAdminNames = sort (a: b: a < b) (attrNames adminUsers);
  firstAdminName = head sortedAdminNames;
  firstAdminUser = adminUsers.${firstAdminName};

  baseUrl = "http://127.0.0.1:${toString cfg.port}";
  cookieFile = "/run/jellyseerr/auth-cookie";
in {
  inherit cookieFile;

  authScript = pkgs.writeShellScript "jellyseerr-auth" ''
    set -euo pipefail

    COOKIE_FILE="${cookieFile}"
    BASE_URL="${baseUrl}"

    # Wait for Jellyseerr to be available
    echo "Waiting for Jellyseerr API..."
    for attempt in {1..60}; do
      if ${pkgs.curl}/bin/curl -sf "$BASE_URL/api/v1/status" >/dev/null 2>&1; then
        echo "Jellyseerr is available"
        break
      fi
      if [[ $attempt -eq 60 ]]; then
        echo "Jellyseerr did not become available" >&2
        exit 1
      fi
      sleep 1
    done

    # Try to use cached cookie
    NEED_AUTH=true
    if [ -f "$COOKIE_FILE" ]; then
      VALIDATE_RESPONSE=$(${pkgs.curl}/bin/curl -s -w "\n%{http_code}" \
        -c "$COOKIE_FILE" \
        "$BASE_URL/api/v1/auth/me" 2>/dev/null || echo -e "\n000")

      VALIDATE_HTTP_CODE=$(echo "$VALIDATE_RESPONSE" | tail -n1)

      if [ "$VALIDATE_HTTP_CODE" = "200" ]; then
        echo "Using cached authentication cookie"
        NEED_AUTH=false
      else
        echo "Cached cookie invalid, re-authenticating..."
        rm -f "$COOKIE_FILE"
      fi
    fi

    # Authenticate if needed
    if [ "$NEED_AUTH" = "true" ]; then
      echo "Authenticating to Jellyseerr as ${firstAdminName}..."

      ${
      if firstAdminUser.password != null
      then secrets.toShellValue "ADMIN_PASSWORD" firstAdminUser.password
      else ''ADMIN_PASSWORD=""''
    }

      BACKOFF=1
      for attempt in {1..10}; do
        AUTH_RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST \
          -c "$COOKIE_FILE" \
          -H "Content-Type: application/json" \
          -d "{\"username\": \"${firstAdminName}\", \"password\": \"$ADMIN_PASSWORD\"}" \
          -w "\n%{http_code}" \
          "$BASE_URL/api/v1/auth/jellyfin" 2>/dev/null || echo -e "\n000")

        AUTH_HTTP_CODE=$(echo "$AUTH_RESPONSE" | tail -n1)

        if [ "$AUTH_HTTP_CODE" = "200" ] || [ "$AUTH_HTTP_CODE" = "201" ]; then
          echo "Successfully authenticated"
          chmod 600 "$COOKIE_FILE"
          break
        fi

        if [[ $attempt -eq 10 ]]; then
          echo "Failed to authenticate after 10 attempts" >&2
          exit 1
        fi

        echo "Authentication attempt $attempt/10 failed (HTTP $AUTH_HTTP_CODE), retrying in $BACKOFF seconds..."
        sleep $BACKOFF
        BACKOFF=$((BACKOFF * 2))
        [ $BACKOFF -gt 8 ] && BACKOFF=8
      done
    fi
  '';
}

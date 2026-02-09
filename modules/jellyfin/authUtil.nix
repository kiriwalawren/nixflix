{
  lib,
  pkgs,
  cfg,
}:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  mkSecureCurl = import ../../lib/mk-secure-curl.nix { inherit lib pkgs; };
  adminUsers = filterAttrs (_: user: user.policy.isAdministrator) cfg.users;
  sortedAdminNames = sort (a: b: a < b) (attrNames adminUsers);
  firstAdminName = head sortedAdminNames;
  firstAdminUser = adminUsers.${firstAdminName};

  baseUrl =
    if cfg.network.baseUrl == "" then
      "http://127.0.0.1:${toString cfg.network.internalHttpPort}"
    else
      "http://127.0.0.1:${toString cfg.network.internalHttpPort}/${cfg.network.baseUrl}";
  tokenFile = "/run/jellyfin/auth-token";
  token = {
    _secret = tokenFile;
  };
  jqTokenSecrets = secrets.mkJqSecretArgs {
    inherit (firstAdminUser) password;
  };
in
{
  inherit token;

  authScript = pkgs.writeShellScript "jellyfin-auth" ''
    set -eu

    TOKEN_FILE="${tokenFile}"

    echo "Waiting for Jellyfin to be available..."
    for attempt in {1..30}; do
      if ${pkgs.curl}/bin/curl -sf "${baseUrl}/System/Info/Public" >/dev/null 2>&1; then
        echo "Jellyfin is available"
        break
      fi
      if [[ $attempt -eq 30 ]]; then
        echo "Jellyfin did not become available after 30 attempts" >&2
        exit 1
      fi
      sleep 1
    done

    NEED_AUTH=true
    TOKEN_PREFIX="MediaBrowser Client=\"nixflix\", Device=\"NixOS\", DeviceId=\"nixflix-auth\", Version=\"1.0.0\""

    if [ -f "$TOKEN_FILE" ]; then
      VALIDATE_RESPONSE=$(${
        mkSecureCurl token {
          url = "${baseUrl}/System/Info";
          extraArgs = "-s -w \"\\n%{http_code}\"";
          apiKeyHeader = "Authorization";
        }
      })

      VALIDATE_HTTP_CODE=$(echo "$VALIDATE_RESPONSE" | tail -n1)

      if [ "$VALIDATE_HTTP_CODE" = "200" ]; then
        echo "Using cached authentication token"
        NEED_AUTH=false
      elif [ "$VALIDATE_HTTP_CODE" = "401" ]; then
        echo "Cached token invalid (401), re-authenticating..."
        ${pkgs.coreutils}/bin/rm -f "$TOKEN_FILE"
      else
        echo "Token validation returned HTTP $VALIDATE_HTTP_CODE, re-authenticating..."
        ${pkgs.coreutils}/bin/rm -f "$TOKEN_FILE"
      fi
    fi

    if [ "$NEED_AUTH" = "true" ]; then
      echo "Authenticating as ${firstAdminName}..."

      ACCESS_TOKEN=""
      BACKOFF=1
      for attempt in {1..10}; do
        AUTH_PAYLOAD_FILE=$(mktemp)
        ${pkgs.jq}/bin/jq -n ${jqTokenSecrets.flagsString} --arg username "${firstAdminName}" '{Username: $username, Pw: ${jqTokenSecrets.refs.password}}' > "$AUTH_PAYLOAD_FILE"

        AUTH_RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST \
          -H "Content-Type: application/json" \
          -H 'Authorization: MediaBrowser Client="nixflix", Device="NixOS", DeviceId="nixflix-auth", Version="1.0.0"' \
          -d "@$AUTH_PAYLOAD_FILE" \
          "${baseUrl}/Users/AuthenticateByName")
        rm -f "$AUTH_PAYLOAD_FILE"

        ACCESS_TOKEN=$(echo "$AUTH_RESPONSE" | ${pkgs.jq}/bin/jq -r '.AccessToken // empty' 2>/dev/null || echo "")

        if [ -n "$ACCESS_TOKEN" ]; then
          echo "Successfully authenticated as ${firstAdminName}"

          echo -n "$TOKEN_PREFIX, Token=\"$ACCESS_TOKEN\"" > "$TOKEN_FILE"
          ${pkgs.coreutils}/bin/chmod 600 "$TOKEN_FILE"

          export ACCESS_TOKEN
          break
        fi

        if [[ $attempt -eq 10 ]]; then
          echo "Failed to authenticate as ${firstAdminName} after 10 attempts" >&2
          echo "Last auth response: $AUTH_RESPONSE" >&2
          exit 1
        fi

        echo "Authentication attempt $attempt/10 failed, retrying in $BACKOFF second(s)..."
        sleep $BACKOFF
        BACKOFF=$((BACKOFF * 2))
        if [ $BACKOFF -gt 8 ]; then
          BACKOFF=8
        fi
      done
    fi
  '';
}

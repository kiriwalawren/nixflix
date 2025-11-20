{
  lib,
  pkgs,
  cfg,
}:
with lib; let
  adminUsers = filterAttrs (_: user: user.policy.isAdministrator) cfg.users;
  sortedAdminNames = sort (a: b: a < b) (attrNames adminUsers);
  firstAdminName = head sortedAdminNames;
  firstAdminUser = adminUsers.${firstAdminName};

  baseUrl = "http://127.0.0.1:${toString cfg.network.internalHttpPort}${cfg.network.baseUrl}";
in {
  authScript = pkgs.writeShellScript "jellyfin-auth" ''
    set -eu

    ${
      if firstAdminUser.passwordFile != null
      then ''ADMIN_PASSWORD=$(${pkgs.coreutils}/bin/cat ${firstAdminUser.passwordFile})''
      else ''ADMIN_PASSWORD=""''
    }

    ACCESS_TOKEN=""
    for attempt in {1..10}; do
      AUTH_RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST \
        -H "Content-Type: application/json" \
        -H 'Authorization: MediaBrowser Client="nixflix", Device="NixOS", DeviceId="nixflix-auth", Version="1.0.0"' \
        -d "{\"Username\": \"${firstAdminName}\", \"Pw\": \"$ADMIN_PASSWORD\"}" \
        "${baseUrl}/Users/AuthenticateByName")

      ACCESS_TOKEN=$(echo "$AUTH_RESPONSE" | ${pkgs.jq}/bin/jq -r '.AccessToken // empty' 2>/dev/null || echo "")

      if [ -n "$ACCESS_TOKEN" ]; then
        echo "Successfully authenticated as ${firstAdminName}"
        export ACCESS_TOKEN
        break
      fi

      if [[ $attempt -eq 10 ]]; then
        echo "Failed to authenticate as ${firstAdminName} after 10 attempts" >&2
        echo "Last auth response: $AUTH_RESPONSE" >&2
        exit 1
      fi

      echo "Authentication attempt $attempt/10 failed, retrying in 1 second..."
      sleep 1
    done
  '';
}

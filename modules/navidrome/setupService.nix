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

  jqAdminSecrets = secrets.mkJqSecretArgs {
    inherit (firstAdminUser) password;
  };

  baseUrl = "http://${cfg.connectionAddress}:${toString cfg.settings.Port}";
in
{
  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.services.navidrome-create-admin = {
      description = "Create first Navidrome admin user";
      after = [ "navidrome.service" ];
      requires = [ "navidrome.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -eu

        BASE_URL="${baseUrl}"

        echo "Waiting for Navidrome to be ready..."
        for i in {1..60}; do
          HTTP_CODE=$(${pkgs.curl}/bin/curl --connect-timeout 5 --max-time 10 -s -o /dev/null -w "%{http_code}" "$BASE_URL/ping" 2>/dev/null || echo "000")
          if [ "$HTTP_CODE" = "200" ]; then
            break
          fi
          if [ "$i" -eq 60 ]; then
            echo "Timeout waiting for Navidrome after 60 attempts" >&2
            exit 1
          fi
          sleep 1
        done

        echo "Creating first admin user: ${firstAdminUser.userName}"

        ADMIN_PAYLOAD=$(${pkgs.jq}/bin/jq -n \
          ${jqAdminSecrets.flagsString} \
          --arg username ${escapeShellArg firstAdminUser.userName} \
          '{username: $username, password: ${jqAdminSecrets.refs.password}}')

        RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST \
          -H "Content-Type: application/json" \
          -d "$ADMIN_PAYLOAD" \
          -w "\n%{http_code}" \
          "$BASE_URL/auth/createAdmin")

        HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
        BODY=$(echo "$RESPONSE" | sed '$d')

        if [ "$HTTP_CODE" = "403" ]; then
          echo "Navidrome admin user already exists, skipping creation"
        elif [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
          echo "Failed to create admin user ${firstAdminUser.userName} (HTTP $HTTP_CODE): $BODY" >&2
          exit 1
        else
          echo "Created admin user ${firstAdminUser.userName}"
        fi
      '';
    };
  };
}

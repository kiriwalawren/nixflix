{
  lib,
  pkgs,
  cfg,
}:
let
  secrets = import ../../lib/secrets { inherit lib; };
  getFirstAdmin = import ../../lib/getFirstAdmin.nix { inherit lib; };

  firstAdminUser =
    (getFirstAdmin {
      inherit (cfg) users;
      isAdmin = user: user.isAdmin;
    }).user;

  jqLoginSecrets = secrets.mkJqSecretArgs { inherit (firstAdminUser) password; };

  baseUrl = "http://${cfg.connectionAddress}:${toString cfg.settings.Port}";
in
{
  inherit baseUrl firstAdminUser;

  # Spliced into a caller's script. Defines nd_login and nd_request METHOD PATH [DATA].
  snippet = ''
    BASE_URL="${baseUrl}"

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

    nd_login() {
      echo "Logging in as ${firstAdminUser.userName}..."
      LOGIN_PAYLOAD=$(${pkgs.jq}/bin/jq -n \
        ${jqLoginSecrets.flagsString} \
        --arg username ${lib.escapeShellArg firstAdminUser.userName} \
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
    }
  '';
}

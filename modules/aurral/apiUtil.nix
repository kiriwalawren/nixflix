{
  lib,
  pkgs,
  cfg,
}:
let
  mkSecureCurl = import ../../lib/mk-secure-curl.nix { inherit lib pkgs; };
in
{
  # Defines BASE_URL and check_response LABEL RESPONSE, which sets BODY and exits on non-2xx.
  preamble = ''
    BASE_URL="http://${cfg.connectionAddress}:${toString cfg.port}"

    check_response() {
      local code
      code=$(echo "$2" | tail -n1)
      BODY=$(echo "$2" | sed '$d')
      if [ "$code" -lt 200 ] || [ "$code" -ge 300 ]; then
        echo "Failed to $1 (HTTP $code): $BODY" >&2
        exit 1
      fi
    }
  '';

  apiCall =
    method: path: data:
    mkSecureCurl cfg.apiKey (
      {
        url = "$BASE_URL/api${path}";
        inherit method;
        extraArgs = ''-w "\n%{http_code}"'';
      }
      // lib.optionalAttrs (data != null) {
        headers."Content-Type" = "application/json";
        inherit data;
      }
    );
}

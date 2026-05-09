{
  lib,
  pkgs,
  cfg,
}:
let
  secrets = import ../../lib/secrets { inherit lib; };

  cookieFile = "/run/seerr/auth-cookie";
  apiKeyHeaderFile = "/run/seerr/api-key-header";

in
{
  inherit cookieFile;

  curlAuthArgs = ''--header @"${apiKeyHeaderFile}"'';

  authScript = pkgs.writeShellScript "seerr-auth" ''
    set -euo pipefail

    SEERR_API_KEY=${secrets.toShellValue cfg.apiKey}
    printf 'X-Api-Key: %s' "$SEERR_API_KEY" > "${apiKeyHeaderFile}"
    chmod 600 "${apiKeyHeaderFile}"
  '';
}

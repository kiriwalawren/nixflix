{
  lib,
  pkgs,
  cfg,
}:
let
  secrets = import ../../lib/secrets { inherit lib; };

  cookieFile = "/run/jellyseerr/auth-cookie";
  apiKeyHeaderFile = "/run/jellyseerr/api-key-header";

in
{
  inherit cookieFile;

  curlAuthArgs = ''--header @"${apiKeyHeaderFile}"'';

  authScript = pkgs.writeShellScript "jellyseerr-auth" ''
    set -euo pipefail

    JELLYSEERR_API_KEY=${secrets.toShellValue cfg.apiKey}
    printf 'X-Api-Key: %s' "$JELLYSEERR_API_KEY" > "${apiKeyHeaderFile}"
    chmod 600 "${apiKeyHeaderFile}"
  '';
}

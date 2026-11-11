{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  inherit (config) nixflix;
  cfg = nixflix.seerr;
  librarySync = import ./librarySync.nix { inherit lib pkgs cfg; };
  baseUrl = "http://${cfg.connectionAddress}:${toString cfg.port}";
in
{
  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.services.seerr-libraries = {
      description = "Sync Seerr library selections";
      after = [
        "seerr-jellyfin.service"
      ]
      ++ optional nixflix.jellyfin.enable "jellyfin-libraries.service";
      requires = [
        "seerr-jellyfin.service"
      ]
      ++ optional nixflix.jellyfin.enable "jellyfin-libraries.service";
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -euo pipefail

        BASE_URL="${baseUrl}"

        source ${librarySync { inherit (cfg) apiKey; }}
      '';
    };
  };
}

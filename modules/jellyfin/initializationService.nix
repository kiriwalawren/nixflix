{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  inherit (config) nixflix;
  cfg = config.nixflix.jellyfin;
in {
  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.services.jellyfin-initialization = {
      description = "Wait for Jellyfin Initialization";
      after = ["jellyfin.service"];
      wants = ["jellyfin.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -eu

        BASE_URL="http://127.0.0.1:${toString cfg.network.internalHttpPort}${cfg.network.baseUrl}"

        echo "Waiting for Jellyfin to finish loading..."
        for i in {1..180}; do
          # Check if API responds with 200 (not 503 "server is loading")
          HTTP_CODE=$(${pkgs.curl}/bin/curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/System/Info/Public" 2>/dev/null || echo "000")

          if [ "$HTTP_CODE" = "200" ]; then
            echo "Jellyfin is ready (HTTP $HTTP_CODE)"
            exit 0
          elif [ "$HTTP_CODE" = "503" ]; then
            echo "Jellyfin is still loading (HTTP 503)... attempt $i/180"
          fi

          if [[ $i -eq 180 ]]; then
            echo "Jellyfin did not finish loading after 180 seconds (last HTTP code: $HTTP_CODE)" >&2
            exit 1
          fi
          sleep 1
        done
      '';
    };
  };
}

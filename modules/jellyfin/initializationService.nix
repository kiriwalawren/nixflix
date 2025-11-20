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

        LOG_FILE="${cfg.logDir}/log_$(${pkgs.coreutils}/bin/date +%Y%m%d).log"
        BASE_URL="http://127.0.0.1:${toString cfg.network.internalHttpPort}${cfg.network.baseUrl}"

        echo "Waiting for Jellyfin to complete startup..."
        for i in {1..60}; do
          if [ -f "$LOG_FILE" ]; then
            if ${pkgs.gnugrep}/bin/grep -q "Startup complete" "$LOG_FILE"; then
              echo "Jellyfin startup complete"
              break
            fi
          fi
          if [[ $i -eq 60 ]]; then
            echo "Jellyfin did not complete startup after 120 seconds" >&2
            exit 1
          fi
          sleep 2
        done

        echo "Waiting for Jellyfin API to be available..."
        for i in {1..90}; do
          if ${pkgs.curl}/bin/curl -s -f "$BASE_URL/System/Ping" >/dev/null 2>&1; then
            echo "Jellyfin API is available"
            exit 0
          fi
          if [[ $i -eq 90 ]]; then
            echo "Jellyfin API not available after 90 seconds" >&2
            exit 1
          fi
          sleep 1
        done
      '';
    };
  };
}

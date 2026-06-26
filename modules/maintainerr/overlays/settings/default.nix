{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix.maintainerr;
  maintainerrUrl = "http://${cfg.connectionAddress}:${toString cfg.port}";
  overlaySettingsJson = builtins.toJSON cfg.overlays.settings;
in
{
  imports = [ ./options.nix ];

  config = mkIf (config.nixflix.enable && cfg.enable) {
    systemd.services.maintainerr-overlays = {
      description = "Configure Maintainerr overlay settings via API";
      after = [
        "maintainerr.service"
        "network-online.target"
      ];
      requires = [ "maintainerr.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "maintainerr-overlays" ''
          set -euo pipefail

          echo "Waiting for Maintainerr to become available..."
          READY=false
          for i in $(seq 1 120); do
            if ${pkgs.curl}/bin/curl -sf "${maintainerrUrl}/api/settings" > /dev/null 2>&1; then
              READY=true
              break
            fi
            sleep 1
          done
          if [ "$READY" != "true" ]; then
            echo "Maintainerr did not become ready after 120s" >&2
            exit 1
          fi

          echo "Applying overlay settings..."
          ${pkgs.curl}/bin/curl -sf -X PUT \
            -H "Content-Type: application/json" \
            --data-binary ${escapeShellArg overlaySettingsJson} \
            "${maintainerrUrl}/api/overlays/settings" \
            | ${pkgs.jq}/bin/jq -e '. != null' > /dev/null

          echo "Maintainerr overlay settings configured successfully."
        '';
      };
    };
  };
}

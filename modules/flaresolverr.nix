{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixflix.flaresolverr;
in
{
  options.nixflix.flaresolverr = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = "Whether or not to enable [FlareSolverr](https://github.com/FlareSolverr/FlareSolverr) for Prowlarr.";
    };

    port = lib.mkOption {
      type = lib.types.number;
      default = 8191;
      description = "Port for FlareSolverr to listen on.";
    };
  };

  config = lib.mkIf (config.nixflix.enable && cfg.enable) {
    services.flaresolverr = {
      enable = true;
      inherit (config.nixflix.flaresolverr) port;
    };

    systemd.services.flaresolverr.serviceConfig.ExecStartPost =
      pkgs.writeShellScript "wait-for-flaresolverr" ''
        for i in $(seq 1 30); do
          if ${pkgs.curl}/bin/curl -sf http://127.0.0.1:${toString cfg.port}/ >/dev/null 2>&1; then
            exit 0
          fi
          sleep 1
        done
        echo "FlareSolverr did not become ready within 30s"
        exit 1
      '';
  };
}

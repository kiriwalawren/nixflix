{ config, lib, ... }:
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
  };
}

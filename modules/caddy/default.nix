{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix;
in
{

  config.services.caddy = mkIf (cfg.enable && cfg.caddy.enable) {
    enable = true;
    package = mkIf cfg.theme.enable (pkgs.callPackage ../../pkgs/caddy-replace-response { });
    globalConfig = ''
      ${optionalString (cfg.caddy.tls.acmeEmail != null) "email ${cfg.caddy.tls.acmeEmail}"}
    '';
  };
}

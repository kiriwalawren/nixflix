{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.nixflix.postgres;
in
{
  options.nixflix.postgres = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable postgresql for the entire stack.
      '';
    };
  };

  config = mkIf (config.nixflix.enable && cfg.enable) {
    services.postgresql = {
      enable = true;
    };

    systemd.targets.postgresql-ready = {
      after = [
        "postgresql.service"
        "postgresql-setup.service"
      ];
      requires = [
        "postgresql.service"
        "postgresql-setup.service"
      ];
      wantedBy = [ "multi-user.target" ];
    };
  };
}

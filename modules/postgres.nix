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
      dataDir = mkIf (config.nixflix.stateDir != "/var/lib") "${config.nixflix.stateDir}/postgres";
    };

    systemd.services.postgresql = {
      after = [ "nixflix-setup-dirs.service" ];
      requires = [ "nixflix-setup-dirs.service" ];
    };

    systemd = {
      tmpfiles.settings."10-postgresql" = mkIf (config.nixflix.stateDir != "/var/lib") {
        "${config.nixflix.stateDir}/postgres".d = {
          user = "postgres";
          group = "postgres";
          mode = "0700";
        };
      };

      targets.postgresql-ready = {
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
  };
}

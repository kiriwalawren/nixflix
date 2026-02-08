{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.nixflix.postgres;
  stateDir = "${config.nixflix.stateDir}/postgres";
in {
  options.nixflix.postgres = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = "Whether or not to enable postgresql for the entire stack";
    };
  };

  config = mkIf (config.nixflix.enable && cfg.enable) {
    services.postgresql = {
      enable = true;
      package = pkgs.postgresql_16;
      dataDir = stateDir;
    };

    systemd = {
      tmpfiles.settings."10-postgresql".${stateDir}.d = {
        user = "postgres";
        group = "postgres";
        mode = "0700";
      };

      targets.postgresql-ready = {
        after = ["postgresql.service" "postgresql-setup.service"];
        requires = ["postgresql.service" "postgresql-setup.service"];
        wantedBy = ["multi-user.target"];
      };
    };
  };
}

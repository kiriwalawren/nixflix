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

    stateDir = mkOption {
      type = types.path;
      default =
        if builtins.pathExists "/var/lib/postgresql/${config.services.postgresql.package.psqlSchema}" then
          "/var/lib/postgresql/${config.services.postgresql.package.psqlSchema}"
        else
          "${config.nixflix.stateDir}/postgres";
      defaultText = ''
        if builtins.pathExists "/var/lib/postgresql/$${config.services.postgresql.package.psqlSchema}" then
          "/var/lib/postgresql/$${config.services.postgresql.package.psqlSchema}"
        else
          "$${config.nixflix.stateDir}/postgres";
      '';
      example = "/var/lib/some/path";
      description = ''
        Path to store the PostgreSQL data.
      '';
    };
  };

  config = mkIf (config.nixflix.enable && cfg.enable) {
    services.postgresql = {
      enable = true;
      dataDir = config.nixflix.postgres.stateDir;
    };

    systemd.services.postgresql = {
      after = [ "nixflix-setup-dirs.service" ];
      requires = [ "nixflix-setup-dirs.service" ];
    };

    systemd = {
      tmpfiles.settings."10-postgresql".${config.nixflix.postgres.stateDir}.d = {
        user = "postgres";
        group = "postgres";
        mode = "0700";
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

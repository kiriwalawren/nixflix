{
  config,
  lib,
  pkgs,
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

        !!! warning

            If you already have `services.postgresql.enable = true;`, then enabling this will break your current
            configuration because `nixflix.postgresql.stateDir` changes the value of `services.postgresql.dataDir`.

            Make sure to update `nixflix.postgresql.stateDir` accordingly.
      '';
    };

    stateDir = mkOption {
      type = types.path;
      default = "${config.nixflix.stateDir}/postgres";
      example = literalExpression ''"/var/lib/postgresql/$${config.services.postgresql.package.psqlSchema}"'';
      description = ''
        Path to store the PostgreSQL data.

        !!! warning

            If you already have `services.postgresql.enable = true;`, then `nixflix.postgresql.enable = true;` will break your current
            configuration because `nixflix.postgresql.stateDir` changes the value of `services.postgresql.dataDir`.

            Make sure to update this option accordingly.
      '';
    };
  };

  config = mkIf (config.nixflix.enable && cfg.enable) {
    services.postgresql = {
      enable = true;
      package = pkgs.postgresql_16;
      dataDir = mkDefault config.nixflix.postgresql.stateDir;
    };

    systemd.services.postgresql = {
      after = [ "nixflix-setup-dirs.service" ];
      requires = [ "nixflix-setup-dirs.service" ];
    };

    systemd = {
      tmpfiles.settings."10-postgresql".${config.nixflix.postgresql.stateDir}.d = {
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

{ serviceName }:
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix.${serviceName};
  inherit (import ./utils.nix { inherit lib pkgs serviceName; }) capitalizedName;
in
{
  config = mkIf (config.nixflix.enable && cfg.enable && config.nixflix.postgres.enable) {
    nixflix.${serviceName}.settings = {
      log.dbEnabled = true;
      postgres = {
        inherit (cfg) user;
        inherit (config.services.postgresql.settings) port;
        host = "/run/postgresql";
        mainDb = cfg.user;
        logDb = "${cfg.user}-logs";
      };
    };

    services.postgresql = {
      ensureDatabases = [
        cfg.settings.postgres.mainDb
        cfg.settings.postgres.logDb
      ];
      ensureUsers = [
        {
          name = cfg.user;
        }
      ];
    };

    systemd.services = {
      "${serviceName}-setup-logs-db" = {
        description = "Grant ownership of ${capitalizedName} databases";
        after = [
          "postgresql.service"
          "postgresql-setup.service"
        ];
        requires = [
          "postgresql.service"
          "postgresql-setup.service"
        ];
        before = [ "postgresql-ready.target" ];
        requiredBy = [ "postgresql-ready.target" ];

        serviceConfig = {
          User = "postgres";
          Group = "postgres";
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          ${pkgs.postgresql}/bin/psql -tAc 'ALTER DATABASE "${cfg.settings.postgres.mainDb}" OWNER TO "${cfg.user}";'
          ${pkgs.postgresql}/bin/psql -tAc 'ALTER DATABASE "${cfg.settings.postgres.logDb}" OWNER TO "${cfg.user}";'
        '';
      };

      "${serviceName}-wait-for-db" = {
        description = "Wait for ${capitalizedName} PostgreSQL databases to be ready";
        after = [
          "postgresql.service"
          "postgresql-setup.service"
        ];
        before = [ "postgresql-ready.target" ];
        requiredBy = [ "postgresql-ready.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "5min";
          User = cfg.user;
          Group = cfg.group;
        };

        script = ''
          while true; do
            if ${pkgs.postgresql}/bin/psql -h /run/postgresql -d ${cfg.user} -c "SELECT 1" > /dev/null 2>&1 && \
               ${pkgs.postgresql}/bin/psql -h /run/postgresql -d ${cfg.user}-logs -c "SELECT 1" > /dev/null 2>&1; then
              echo "${capitalizedName} PostgreSQL databases are ready"
              exit 0
            fi
            echo "Waiting for ${capitalizedName} PostgreSQL databases..."
            sleep 1
          done
        '';
      };

      ${serviceName} = {
        after = [ "postgresql-ready.target" ];
        requires = [ "postgresql-ready.target" ];
      };
    };
  };
}

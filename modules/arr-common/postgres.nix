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
  pgCfg = config.nixflix.postgres;
  isLocal = pgCfg.host == null;
  secrets = import ../../lib/secrets { inherit lib; };
  inherit (import ./utils.nix { inherit lib pkgs serviceName; }) capitalizedName;
  passwordIsSecretRef = cfg.postgres.password != null && secrets.isSecretRef cfg.postgres.password;
  psqlConnArgs =
    if isLocal then
      "-h /run/postgresql"
    else
      "-h ${escapeShellArg pgCfg.host} -p ${toString pgCfg.port} -U ${escapeShellArg cfg.settings.postgres.user}";
in
{
  options.nixflix.${serviceName}.postgres.password = secrets.mkSecretOption {
    nullable = true;
    default = null;
    description = ''
      Password ${capitalizedName} uses to connect to the external PostgreSQL
      server set in `nixflix.postgres.host`. Required when that option is set,
      ignored for the local server. ${capitalizedName} connects as the role
      `nixflix.${serviceName}.user` to the databases `<user>` and
      `<user>-logs`, which must already exist (see `nixflix.postgres.host`).
    '';
  };

  config = mkIf (config.nixflix.enable && cfg.enable && pgCfg.enable) (mkMerge [
    {
      assertions = [
        {
          assertion = !isLocal -> cfg.postgres.password != null;
          message = "`nixflix.postgres.host` is set, so ${capitalizedName} needs a database password. Set `nixflix.${serviceName}.postgres.password`.";
        }
      ];

      nixflix.${serviceName}.settings = {
        log.dbEnabled = true;
        postgres = {
          inherit (cfg) user;
          host = if isLocal then "/run/postgresql" else pgCfg.host;
          port = if isLocal then config.services.postgresql.settings.port else pgCfg.port;
          mainDb = cfg.user;
          logDb = "${cfg.user}-logs";
        };
      };

      systemd.services = {
        "${serviceName}-wait-for-db" = {
          description = "Wait for ${capitalizedName} PostgreSQL databases to be ready";
          after =
            if isLocal then
              [
                "postgresql.service"
                "postgresql-setup.service"
              ]
            else
              [ "network-online.target" ];
          wants = optional (!isLocal) "network-online.target";
          before = [ "postgresql-ready.target" ];
          requiredBy = [ "postgresql-ready.target" ];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            TimeoutStartSec = "5min";
            User = cfg.user;
            Group = cfg.group;
          }
          // optionalAttrs (!isLocal && passwordIsSecretRef) {
            LoadCredential = [ "dbPassword:${toString cfg.postgres.password._secret}" ];
          };

          environment = optionalAttrs (!isLocal && cfg.postgres.password != null && !passwordIsSecretRef) {
            PGPASSWORD = toString cfg.postgres.password;
          };

          script = ''
            ${optionalString (!isLocal && passwordIsSecretRef) ''
              PGPASSWORD="$(cat "$CREDENTIALS_DIRECTORY/dbPassword")"
              export PGPASSWORD
            ''}
            while true; do
              if ${pkgs.postgresql}/bin/psql ${psqlConnArgs} -d ${escapeShellArg cfg.settings.postgres.mainDb} -c "SELECT 1" > /dev/null 2>&1 && \
                 ${pkgs.postgresql}/bin/psql ${psqlConnArgs} -d ${escapeShellArg cfg.settings.postgres.logDb} -c "SELECT 1" > /dev/null 2>&1; then
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
    }
    (mkIf isLocal {
      services.postgresql = {
        ensureDatabases = [
          cfg.settings.postgres.mainDb
          cfg.settings.postgres.logDb
        ];
        ensureUsers = [ { name = cfg.user; } ];
      };

      systemd.services."${serviceName}-setup-logs-db" = {
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
    })
  ]);
}

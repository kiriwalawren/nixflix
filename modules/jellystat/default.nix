{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  inherit (import ../../lib/mkVirtualHosts.nix { inherit lib config; }) mkVirtualHost;
  cfg = config.nixflix.jellystat;
  hostname = "${cfg.subdomain}.${config.nixflix.reverseProxy.domain}";

  jellyfinUrl =
    if cfg.jellyfin.urlBase == "" then
      "${if cfg.jellyfin.useSsl then "https" else "http"}://${cfg.jellyfin.hostname}:${toString cfg.jellyfin.port}"
    else
      "${if cfg.jellyfin.useSsl then "https" else "http"}://${cfg.jellyfin.hostname}:${toString cfg.jellyfin.port}/${cfg.jellyfin.urlBase}";
  generatedJwtSecret = pkgs.lib.mkStrongPassword;
in
{
  imports = [
    ./options
  ];

  config = mkIf (config.nixflix.enable && cfg.enable) (mkMerge [
    (mkVirtualHost {
      inherit hostname;
      inherit (cfg.reverseProxy) expose;
      inherit (cfg) port;
      upstreamHost = cfg.connectionAddress;
      themeParkService = "jellystat";
    })
    {
      assertions = [
        {
          assertion = config.nixflix.postgres.enable;
          message = "Jellystat requires PostgreSQL to be enabled. Please set nixflix.postgres.enable = true.";
        }
      ];

      users = {
        groups.${cfg.group} = {
          gid = mkForce config.nixflix.globals.gids.jellystat;
        };

        users.${cfg.user} = {
          inherit (cfg) group;
          home = cfg.dataDir;
          isSystemUser = true;
          uid = mkForce config.nixflix.globals.uids.jellystat;
        };
      };

      systemd.tmpfiles.settings."10-jellystat" = {
        "/run/jellystat".d = {
          mode = "0755";
          inherit (cfg) user;
          inherit (cfg) group;
        };
        "${cfg.dataDir}".d = {
          mode = "0755";
          inherit (cfg) user;
          inherit (cfg) group;
        };
        "${cfg.backupDir}".d = {
          mode = "0755";
          inherit (cfg) user;
          inherit (cfg) group;
        };
      };

      services.postgresql = mkIf config.nixflix.postgres.enable {
        ensureDatabases = [ cfg.user ];
        ensureUsers = [
          {
            name = cfg.user;
            ensureDBOwnership = true;
          }
        ];
      };

      systemd.services = {
        jellystat-env = {
          description = "Setup Jellystat environment file";
          wantedBy = [ "jellystat.service" ];
          before = [ "jellystat.service" ];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };

          script = ''
            mkdir -p /run/jellystat
            echo "JWT_SECRET=${secrets.toShellValue (cfg.jwtSecret or generatedJwtSecret)}" > /run/jellystat/env
            echo "JF_API_KEY=${secrets.toShellValue cfg.jellyfin.apiKey}" >> /run/jellystat/env
            ${optionalString
              (cfg.jellyfin.masterOverrideUser != null && cfg.jellyfin.masterOverridePassword != null)
              ''
                echo "JS_USER=${secrets.toShellValue cfg.jellyfin.masterOverrideUser}" >> /run/jellystat/env
                echo "JS_PASSWORD=${secrets.toShellValue cfg.jellyfin.masterOverridePassword}" >> /run/jellystat/env
              ''
            }
            chown ${cfg.user}:${cfg.group} /run/jellystat/env
            chmod 0400 /run/jellystat/env
          '';
        };

        jellystat-wait-for-db = mkIf config.nixflix.postgres.enable {
          description = "Wait for Jellystat PostgreSQL database to be ready";
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
              if ${pkgs.postgresql}/bin/psql -h /run/postgresql -d ${cfg.user} -c "SELECT 1" > /dev/null 2>&1; then
                echo "Jellystat PostgreSQL database is ready"
                exit 0
              fi
              echo "Waiting for PostgreSQL database ${cfg.user}..."
              sleep 1
            done
          '';
        };

        jellystat = {
          description = "Jellystat statistics for Jellyfin";

          after = [
            "network-online.target"
            "nixflix-setup-dirs.service"
            "jellystat-env.service"
            "postgresql-ready.target"
          ]
          ++ optional config.nixflix.jellyfin.enable "jellyfin-setup-wizard.service";

          wants = [
            "network-online.target"
          ];

          requires = [
            "nixflix-setup-dirs.service"
            "jellystat-env.service"
            "postgresql-ready.target"
          ]
          ++ optional config.nixflix.jellyfin.enable "jellyfin-setup-wizard.service";

          wantedBy = [ "multi-user.target" ];

          environment = {
            HOST = mkIf config.nixflix.reverseProxy.enable "127.0.0.1";
            PORT = toString cfg.port;
            JS_LISTEN_IP = "0.0.0.0";
            POSTGRES_USER = cfg.user;
            POSTGRES_PASSWORD = "";
            POSTGRES_IP = "/run/postgresql";
            POSTGRES_PORT = toString config.services.postgresql.settings.port;
            POSTGRES_DB = cfg.user;
            JF_HOST = jellyfinUrl;
            JF_USE_WEBSOCKETS = if cfg.useWebsockets then "true" else "false";
            IS_EMBY_API = if cfg.isEmby then "true" else "false";
            TZ = cfg.timezone;
            NEW_WATCH_EVENT_THRESHOLD_HOURS = toString cfg.watchSessionThreshold;
            REJECT_SELF_SIGNED_CERTIFICATES = "false";
          };

          serviceConfig = {
            Type = "simple";
            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = cfg.dataDir;
            Restart = "on-failure";
            RestartSec = "10s";

            ExecStart = "${getExe' cfg.package "jellystat"}";

            EnvironmentFile = "/run/jellystat/env";

            NoNewPrivileges = true;
            PrivateTmp = true;
            PrivateDevices = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ReadWritePaths = [
              cfg.dataDir
              cfg.backupDir
            ];
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_INET"
              "AF_INET6"
              "AF_NETLINK"
            ];
            LockPersonality = true;
            ProtectControlGroups = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            RestrictNamespaces = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            SystemCallArchitectures = "native";
            SystemCallFilter = [
              "~@clock"
              "~@debug"
              "~@module"
              "~@mount"
              "~@reboot"
              "~@swap"
              "~@privileged"
              "~@resources"
            ];
          };
        };
      };

      networking.firewall = mkIf cfg.openFirewall {
        allowedTCPPorts = [ cfg.port ];
      };
    }
    (mkIf (config.nixflix.vpn.enable && cfg.vpn.enable) {
      systemd.services.jellystat.vpnConfinement = {
        enable = true;
        vpnNamespace = "wg";
      };
      vpnNamespaces.wg.portMappings = [
        {
          from = cfg.port;
          to = cfg.port;
          protocol = "tcp";
        }
      ];
    })
  ]);
}

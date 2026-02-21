{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  inherit (config) nixflix;
  inherit (nixflix) globals;
  cfg = config.nixflix.jellyseerr;
  hostname = "${cfg.subdomain}.${nixflix.nginx.domain}";
in
{
  imports = [
    ./jellyfinService.nix
    ./librarySyncService.nix
    ./options
    ./radarrService.nix
    ./setupService.nix
    ./sonarrService.nix
    ./userSettingsService.nix
  ];

  config = mkIf (nixflix.enable && cfg.enable) {
    assertions =
      let
        radarrDefaults = filter (r: r.isDefault) (attrValues cfg.radarr);
        radarrDefaultCount = length radarrDefaults;
        radarrDefault4k = filter (r: r.is4k) radarrDefaults;
        radarrDefaultNon4k = filter (r: !r.is4k) radarrDefaults;

        sonarrDefaults = filter (s: s.isDefault) (attrValues cfg.sonarr);
        sonarrDefaultCount = length sonarrDefaults;
        sonarrDefault4k = filter (s: s.is4k) sonarrDefaults;
        sonarrDefaultNon4k = filter (s: !s.is4k) sonarrDefaults;
      in
      [
        {
          assertion = cfg.vpn.enable -> nixflix.mullvad.enable;
          message = "Cannot enable VPN routing for Jellyseerr (nixflix.jellyseerr.vpn.enable = true) when Mullvad VPN is disabled. Please set nixflix.mullvad.enable = true.";
        }
        {
          assertion = radarrDefaultCount <= 2;
          message = "Cannot have more than 2 default Radarr instances in jellyseerr.radarr. Found ${toString radarrDefaultCount} instances with isDefault = true.";
        }
        {
          assertion =
            radarrDefaultCount != 2 || (length radarrDefault4k == 1 && length radarrDefaultNon4k == 1);
          message = "When there are 2 default Radarr instances, one must be 4K (is4k = true) and one must be non-4K (is4k = false).";
        }
        {
          assertion = sonarrDefaultCount <= 2;
          message = "Cannot have more than 2 default Sonarr instances in jellyseerr.sonarr. Found ${toString sonarrDefaultCount} instances with isDefault = true.";
        }
        {
          assertion =
            sonarrDefaultCount != 2 || (length sonarrDefault4k == 1 && length sonarrDefaultNon4k == 1);
          message = "When there are 2 default Sonarr instances, one must be 4K (is4k = true) and one must be non-4K (is4k = false).";
        }
      ];

    users = {
      groups.${cfg.group} = {
        gid = mkForce globals.gids.jellyseerr;
      };

      users.${cfg.user} = {
        inherit (cfg) group;
        home = cfg.dataDir;
        isSystemUser = true;
        uid = mkForce globals.uids.jellyseerr;
      };
    };

    systemd.tmpfiles.settings."10-jellyseerr" = {
      "/run/jellyseerr".d = {
        mode = "0755";
        inherit (cfg) user;
        inherit (cfg) group;
      };
      "${cfg.dataDir}".d = {
        mode = "0755";
        inherit (cfg) user;
        inherit (cfg) group;
      };
    };

    services.postgresql = mkIf config.services.postgresql.enable {
      ensureDatabases = [ cfg.user ];
      ensureUsers = [
        {
          name = cfg.user;
          ensureDBOwnership = true;
        }
      ];
    };

    systemd.services = {
      jellyseerr-env = mkIf (cfg.apiKey != null) {
        description = "Setup Jellyseerr environment file";
        wantedBy = [ "jellyseerr.service" ];
        before = [ "jellyseerr.service" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          mkdir -p /run/jellyseerr
          echo "API_KEY=${secrets.toShellValue cfg.apiKey}" > /run/jellyseerr/env
          chown ${cfg.user}:${cfg.group} /run/jellyseerr/env
          chmod 0400 /run/jellyseerr/env
        '';
      };

      jellyseerr-wait-for-db = mkIf config.services.postgresql.enable {
        description = "Wait for Jellyseerr PostgreSQL database to be ready";
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
              echo "Jellyseerr PostgreSQL database is ready"
              exit 0
            fi
            echo "Waiting for PostgreSQL role jellyseerr..."
            sleep 1
          done
        '';
      };

      jellyseerr = {
        description = "Jellyseerr media request manager";

        after = [
          "network-online.target"
          "nixflix-setup-dirs.service"
        ]
        ++ optional (cfg.apiKey != null) "jellyseerr-env.service"
        ++ optional nixflix.mullvad.enable "mullvad-config.service"
        ++ optional nixflix.jellyfin.enable "jellyfin.service"
        ++ optional config.services.postgresql.enable "postgresql-ready.target";

        wants = [
          "network-online.target"
        ]
        ++ optional nixflix.mullvad.enable "mullvad-config.service"
        ++ optional nixflix.jellyfin.enable "jellyfin.service";

        requires = [
          "nixflix-setup-dirs.service"
        ]
        ++ optional (cfg.apiKey != null) "jellyseerr-env.service"
        ++ optional config.services.postgresql.enable "postgresql-ready.target";

        wantedBy = [ "multi-user.target" ];

        environment = {
          HOST = mkIf config.nixflix.nginx.enable "127.0.0.1";
          PORT = toString cfg.port;
          CONFIG_DIRECTORY = cfg.dataDir;
        }
        // optionalAttrs config.services.postgresql.enable {
          DB_TYPE = "postgres";
          DB_SOCKET_PATH = "/run/postgresql";
          DB_USER = cfg.user;
          DB_NAME = cfg.user;
          DB_LOG_QUERIES = "false";
        };

        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          WorkingDirectory = cfg.dataDir;
          Restart = "on-failure";

          ExecStart =
            if (nixflix.mullvad.enable && !cfg.vpn.enable) then
              pkgs.writeShellScript "jellyseerr-vpn-bypass" ''
                exec /run/wrappers/bin/mullvad-exclude ${getExe cfg.package}
              ''
            else
              "${getExe cfg.package}";

          # Security hardening
          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = cfg.dataDir;
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_INET"
            "AF_INET6"
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
        }
        // optionalAttrs (cfg.apiKey != null) {
          EnvironmentFile = "/run/jellyseerr/env";
        }
        // optionalAttrs (nixflix.mullvad.enable && !cfg.vpn.enable) {
          AmbientCapabilities = "CAP_SYS_ADMIN";
          Delegate = mkForce true;
          SystemCallFilter = mkForce [ ];
          NoNewPrivileges = mkForce false;
          ProtectControlGroups = mkForce false;
        };
      };
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
    };

    networking.hosts = mkIf (nixflix.nginx.enable && nixflix.nginx.addHostsEntries) {
      "127.0.0.1" = [ hostname ];
    };

    services.nginx.virtualHosts."${hostname}" =
      let
        themeParkUrl = "https://theme-park.dev/css/base/overseerr/${nixflix.theme.name}.css";
      in
      mkIf nixflix.nginx.enable {
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
          recommendedProxySettings = true;
          extraConfig = ''
            proxy_redirect off;

            ${
              if nixflix.theme.enable then
                ''
                  proxy_set_header Accept-Encoding "";
                  sub_filter '</head>' '<link rel="stylesheet" type="text/css" href="${themeParkUrl}"></head>';
                  sub_filter_once on;
                ''
              else
                ""
            }
          '';
        };
      };
  };
}

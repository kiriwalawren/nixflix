{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  secrets = import ../lib/secrets {inherit lib;};
  inherit (config) nixflix;
  inherit (nixflix) globals;
  cfg = config.nixflix.seerr;
in {
  imports = [
    ./options
    ./setupService.nix
    ./userSettingsService.nix
    ./librarySyncService.nix
    ./radarrService.nix
    ./sonarrService.nix
  ];

  config = mkIf (nixflix.enable && cfg.enable) {
    assertions = let
      radarrDefaults = filter (r: r.isDefault) cfg.radarr;
      radarrDefaultCount = length radarrDefaults;
      radarrDefault4k = filter (r: r.is4k) radarrDefaults;
      radarrDefaultNon4k = filter (r: !r.is4k) radarrDefaults;

      sonarrDefaults = filter (s: s.isDefault) cfg.sonarr;
      sonarrDefaultCount = length sonarrDefaults;
      sonarrDefault4k = filter (s: s.is4k) sonarrDefaults;
      sonarrDefaultNon4k = filter (s: !s.is4k) sonarrDefaults;
    in [
      {
        assertion = cfg.vpn.enable -> nixflix.mullvad.enable;
        message = "Cannot enable VPN routing for Seerr (nixflix.seerr.vpn.enable = true) when Mullvad VPN is disabled. Please set nixflix.mullvad.enable = true.";
      }
      {
        assertion = radarrDefaultCount <= 2;
        message = "Cannot have more than 2 default Radarr instances in seerr.radarr. Found ${toString radarrDefaultCount} instances with isDefault = true.";
      }
      {
        assertion = radarrDefaultCount != 2 || (length radarrDefault4k == 1 && length radarrDefaultNon4k == 1);
        message = "When there are 2 default Radarr instances, one must be 4K (is4k = true) and one must be non-4K (is4k = false).";
      }
      {
        assertion = sonarrDefaultCount <= 2;
        message = "Cannot have more than 2 default Sonarr instances in seerr.sonarr. Found ${toString sonarrDefaultCount} instances with isDefault = true.";
      }
      {
        assertion = sonarrDefaultCount != 2 || (length sonarrDefault4k == 1 && length sonarrDefaultNon4k == 1);
        message = "When there are 2 default Sonarr instances, one must be 4K (is4k = true) and one must be non-4K (is4k = false).";
      }
    ];

    users = {
      groups.${cfg.group} = {
        gid = mkForce globals.gids.seerr;
      };

      users.${cfg.user} = {
        inherit (cfg) group;
        home = cfg.dataDir;
        isSystemUser = true;
        uid = mkForce globals.uids.seerr;
      };
    };

    systemd.tmpfiles.rules = [
      "d '${cfg.dataDir}' 0750 ${cfg.user} ${cfg.group} - -"
    ];

    services.postgresql = mkIf config.services.postgresql.enable {
      ensureDatabases = [cfg.user];
      ensureUsers = [
        {
          name = cfg.user;
          ensureDBOwnership = true;
        }
      ];
    };

    systemd.services = {
      seerr-env = mkIf (cfg.apiKey != null) {
        description = "Setup Seerr environment file";
        wantedBy = ["seerr.service"];
        before = ["seerr.service"];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          mkdir -p /run/seerr
          ${secrets.toShellValue "API_KEY" cfg.apiKey}
          echo "API_KEY=''${API_KEY}" > /run/seerr/env
          chown ${cfg.user}:${cfg.group} /run/seerr/env
          chmod 0400 /run/seerr/env
        '';
      };

      seerr-wait-for-db = mkIf config.services.postgresql.enable {
        description = "Wait for Seerr PostgreSQL database to be ready";
        after = ["postgresql.service" "postgresql-setup.service"];
        before = ["postgresql-ready.target"];
        requiredBy = ["postgresql-ready.target"];

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
              echo "Seerr PostgreSQL database is ready"
              exit 0
            fi
            echo "Waiting for PostgreSQL role seerr..."
            sleep 1
          done
        '';
      };

      seerr = {
        description = "Seerr media request manager";

        after =
          ["network-online.target"]
          ++ optional (cfg.apiKey != null) "seerr-env.service"
          ++ optional nixflix.mullvad.enable "mullvad-config.service"
          ++ optional nixflix.jellyfin.enable "jellyfin.service"
          ++ optional config.services.postgresql.enable "postgresql-ready.target";

        wants =
          ["network-online.target"]
          ++ optional nixflix.mullvad.enable "mullvad-config.service"
          ++ optional nixflix.jellyfin.enable "jellyfin.service";

        requires =
          optional (cfg.apiKey != null) "seerr-env.service"
          ++ optional config.services.postgresql.enable "postgresql-ready.target";

        wantedBy = ["multi-user.target"];

        environment =
          {
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

        serviceConfig =
          {
            Type = "simple";
            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = cfg.dataDir;
            Restart = "on-failure";

            ExecStart =
              if (nixflix.mullvad.enable && !cfg.vpn.enable)
              then
                pkgs.writeShellScript "seerr-vpn-bypass" ''
                  exec /run/wrappers/bin/mullvad-exclude ${getExe cfg.package}
                ''
              else "${getExe cfg.package}";

            # Security hardening
            NoNewPrivileges = true;
            PrivateTmp = true;
            PrivateDevices = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ReadWritePaths = cfg.dataDir;
            RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
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
            EnvironmentFile = "/run/seerr/env";
          }
          // optionalAttrs (nixflix.mullvad.enable && !cfg.vpn.enable) {
            AmbientCapabilities = "CAP_SYS_ADMIN";
            Delegate = mkForce true;
            SystemCallFilter = mkForce [];
            NoNewPrivileges = mkForce false;
            ProtectControlGroups = mkForce false;
          };
      };
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [cfg.port];
    };

    services.nginx = mkIf nixflix.nginx.enable {
      virtualHosts.localhost.locations."^~ /seerr" = let
        themeParkUrl = "https://theme-park.dev/css/base/overseerr/${nixflix.theme.name}.css";
      in {
        proxyPass = "http://127.0.0.1:${toString cfg.port}";
        recommendedProxySettings = true;
        extraConfig = ''
          # Remove /seerr path to pass to the app
          rewrite ^/seerr/?(.*)$ /$1 break;

          # Redirect location headers
          proxy_redirect ^ /seerr;
          proxy_redirect /setup /seerr/setup;
          proxy_redirect /login /seerr/login;

          # Sub filters to replace hardcoded paths
          proxy_set_header Accept-Encoding "";
          sub_filter_once off;
          sub_filter_types *;
          sub_filter 'href="/"' 'href="/seerr"';
          sub_filter 'href="/login"' 'href="/seerr/login"';
          sub_filter 'href:"/"' 'href:"/seerr"';
          sub_filter '\/_next' '\/seerr\/_next';
          sub_filter '/_next' '/seerr/_next';
          sub_filter '/api/v1' '/seerr/api/v1';
          sub_filter '/login/plex/loading' '/seerr/login/plex/loading';
          sub_filter '/images/' '/seerr/images/';
          sub_filter '/imageproxy/' '/seerr/imageproxy/';
          sub_filter '/avatarproxy/' '/seerr/avatarproxy/';
          sub_filter '/android-' '/seerr/android-';
          sub_filter '/apple-' '/seerr/apple-';
          sub_filter '/favicon' '/seerr/favicon';
          sub_filter '/logo_' '/seerr/logo_';
          sub_filter '/site.webmanifest' '/seerr/site.webmanifest';

          ${
            if nixflix.theme.enable
            then ''
              sub_filter '</body>' '<link rel="stylesheet" type="text/css" href="${themeParkUrl}"></body>';
            ''
            else ""
          }
        '';
      };
    };
  };
}

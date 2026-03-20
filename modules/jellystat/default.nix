{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  cfg = config.nixflix.jellystat;
  hostname = "${cfg.subdomain}.${config.nixflix.nginx.domain}";

  jellyfinApiKey =
    if cfg.jellyfin.apiKey != null then
      cfg.jellyfin.apiKey
    else if config.nixflix.jellyfin.enable && config.nixflix.jellyfin.config.apiKey != null then
      config.nixflix.jellyfin.config.apiKey
    else
      null;

  jellyfinHostname =
    if cfg.jellyfin.hostname != "127.0.0.1" || cfg.jellyfin.port != 8096 then
      { inherit (cfg.jellyfin) hostname port useSsl urlBase; }
    else if config.nixflix.jellyfin.enable then
      {
        hostname = "127.0.0.1";
        port = config.nixflix.jellyfin.network.internalHttpPort;
        useSsl = false;
        urlBase = config.nixflix.jellyfin.network.baseUrl;
      }
    else
      cfg.jellyfin;

  jellyfinUrl =
    if jellyfinHostname.urlBase == "" then
      "${if jellyfinHostname.useSsl then "https" else "http"}://${jellyfinHostname.hostname}:${toString jellyfinHostname.port}"
    else
      "${if jellyfinHostname.useSsl then "https" else "http"}://${jellyfinHostname.hostname}:${toString jellyfinHostname.port}/${jellyfinHostname.urlBase}";
in
{
  imports = [
    ./options
  ];

  config = mkIf (config.nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.vpn.enable -> config.nixflix.mullvad.enable;
        message = "Cannot enable VPN routing for Jellystat (nixflix.jellystat.vpn.enable = true) when Mullvad VPN is disabled. Please set nixflix.mullvad.enable = true.";
      }
      {
        assertion = jellyfinApiKey != null;
        message = "Jellystat requires a Jellyfin API key. Please set nixflix.jellystat.jellyfin.apiKey or enable nixflix.jellyfin with a configured API key.";
      }
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
      ensureDatabases = [ cfg.database.name ];
      ensureUsers = [
        {
          name = cfg.user;
          ensureDBOwnership = true;
        }
      ];
    };

    systemd.services = {
      jellystat-env = mkIf (cfg.jwtSecret != null || jellyfinApiKey != null) {
        description = "Setup Jellystat environment file";
        wantedBy = [ "jellystat.service" ];
        before = [ "jellystat.service" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          mkdir -p /run/jellystat
          ${optionalString (cfg.jwtSecret != null) ''echo "JWT_SECRET=${secrets.toShellValue cfg.jwtSecret}" > /run/jellystat/env''}
          ${optionalString (jellyfinApiKey != null) ''echo "JF_API_KEY=${secrets.toShellValue jellyfinApiKey}" >> /run/jellystat/env''}
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
            if ${pkgs.postgresql}/bin/psql -h /run/postgresql -d ${cfg.database.name} -c "SELECT 1" > /dev/null 2>&1; then
              echo "Jellystat PostgreSQL database is ready"
              exit 0
            fi
            echo "Waiting for PostgreSQL database ${cfg.database.name}..."
            sleep 1
          done
        '';
      };

      jellystat = {
        description = "Jellystat statistics for Jellyfin";

        after = [
          "network-online.target"
          "nixflix-setup-dirs.service"
        ]
        ++ optional (cfg.jwtSecret != null || jellyfinApiKey != null) "jellystat-env.service"
        ++ optional config.nixflix.postgres.enable "postgresql-ready.target"
        ++ optional config.nixflix.mullvad.enable "mullvad-config.service"
        ++ optional config.nixflix.jellyfin.enable "jellyfin.service";

        wants = [
          "network-online.target"
        ]
        ++ optional config.nixflix.mullvad.enable "mullvad-config.service";

        requires = [
          "nixflix-setup-dirs.service"
        ]
        ++ optional (cfg.jwtSecret != null || jellyfinApiKey != null) "jellystat-env.service"
        ++ optional config.nixflix.postgres.enable "postgresql-ready.target";

        wantedBy = [ "multi-user.target" ];

        environment = {
          HOST = mkIf config.nixflix.nginx.enable "127.0.0.1";
          PORT = toString cfg.port;
          JS_LISTEN_IP = "0.0.0.0";
          POSTGRES_USER = cfg.user;
          POSTGRES_IP = "127.0.0.1";
          POSTGRES_PORT = toString config.services.postgresql.settings.port;
          POSTGRES_DB = cfg.database.name;
          POSTGRES_SSL_ENABLED = "false";
          POSTGRES_SSL_REJECT_UNAUTHORIZED = "false";
          JF_HOST = jellyfinUrl;
          JF_USE_WEBSOCKETS = if cfg.useWebsockets then "true" else "false";
          IS_EMBY_API = if cfg.isEmby then "true" else "false";
          TZ = "UTC";
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

          ExecStart =
            if (config.nixflix.mullvad.enable && !cfg.vpn.enable) then
              pkgs.writeShellScript "jellystat-vpn-bypass" ''
                exec /run/wrappers/bin/mullvad-exclude ${getExe cfg.package}
              ''
            else
              "${getExe cfg.package}";

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
        // optionalAttrs (cfg.jwtSecret != null || jellyfinApiKey != null) {
          EnvironmentFile = "/run/jellystat/env";
        }
        // optionalAttrs (config.nixflix.mullvad.enable && !cfg.vpn.enable) {
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

    networking.hosts = mkIf (config.nixflix.nginx.enable && config.nixflix.nginx.addHostsEntries) {
      "127.0.0.1" = [ hostname ];
    };

    services.nginx.virtualHosts."${hostname}" =
      let
        themeParkUrl = "https://theme-park.dev/css/base/jellystat/${config.nixflix.theme.name}.css";
      in
      mkIf config.nixflix.nginx.enable {
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
          recommendedProxySettings = true;
          extraConfig = ''
            proxy_redirect off;

            ${
              if config.nixflix.theme.enable then
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

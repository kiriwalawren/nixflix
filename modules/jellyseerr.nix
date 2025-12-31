{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  inherit (config) nixflix;
  inherit (nixflix) globals;
  cfg = config.nixflix.jellyseerr;
  stateDir = "${nixflix.stateDir}/jellyseerr";
in {
  options.nixflix.jellyseerr = {
    enable = mkEnableOption "Jellyseerr media request manager";

    package = mkPackageOption pkgs "jellyseerr" {};

    apiKeyPath = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to API key secret file";
    };

    user = mkOption {
      type = types.str;
      default = "jellyseerr";
      description = "User under which the service runs";
    };

    group = mkOption {
      type = types.str;
      default = "jellyseerr";
      description = "Group under which the service runs";
    };

    dataDir = mkOption {
      type = types.path;
      default = stateDir;
      defaultText = literalExpression ''"''${nixflix.stateDir}/jellyseerr"'';
      description = "Directory containing jellyseerr data and configuration";
    };

    port = mkOption {
      type = types.port;
      default = 5055;
      description = "Port on which jellyseerr listens";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open port in firewall for jellyseerr";
    };

    vpn = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to route Jellyseerr traffic through the VPN.
          When true (default), Jellyseerr routes through the VPN (requires nixflix.mullvad.enable = true).
          When false, Jellyseerr bypasses the VPN.
        '';
      };
    };
  };

  config = mkIf (nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.vpn.enable -> nixflix.mullvad.enable;
        message = "Cannot enable VPN routing for Jellyseerr (nixflix.jellyseerr.vpn.enable = true) when Mullvad VPN is disabled. Please set nixflix.mullvad.enable = true.";
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
      jellyseerr-env = mkIf (cfg.apiKeyPath != null) {
        description = "Setup Jellyseerr environment file";
        wantedBy = ["jellyseerr.service"];
        before = ["jellyseerr.service"];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          mkdir -p /run/jellyseerr
          echo "API_KEY=$(cat ${cfg.apiKeyPath})" > /run/jellyseerr/env
          chown ${cfg.user}:${cfg.group} /run/jellyseerr/env
          chmod 0400 /run/jellyseerr/env
        '';
      };

      jellyseerr-wait-for-db = mkIf config.services.postgresql.enable {
        description = "Wait for Jellyseerr PostgreSQL database to be ready";
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

        after =
          ["network-online.target"]
          ++ optional (cfg.apiKeyPath != null) "jellyseerr-env.service"
          ++ optional nixflix.mullvad.enable "mullvad-config.service"
          ++ optional nixflix.jellyfin.enable "jellyfin.service"
          ++ optional config.services.postgresql.enable "postgresql-ready.target";

        wants =
          ["network-online.target"]
          ++ optional nixflix.mullvad.enable "mullvad-config.service"
          ++ optional nixflix.jellyfin.enable "jellyfin.service";

        requires =
          optional (cfg.apiKeyPath != null) "jellyseerr-env.service"
          ++ optional config.services.postgresql.enable "postgresql-ready.target";

        wantedBy = ["multi-user.target"];

        environment = {
          PORT = toString cfg.port;
          CONFIG_DIRECTORY = cfg.dataDir;
        };
        # TODO uncomment after done testing
        # // optionalAttrs config.services.postgresql.enable {
        #   DB_TYPE = "postgres";
        #   DB_SOCKET_PATH = "/run/postgresql";
        #   DB_USER = cfg.user;
        #   DB_NAME = cfg.user;
        #   DB_LOG_QUERIES = "false";
        # };

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
                pkgs.writeShellScript "jellyseerr-vpn-bypass" ''
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
          // optionalAttrs (cfg.apiKeyPath != null) {
            EnvironmentFile = "/run/jellyseerr/env";
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
      virtualHosts.localhost.locations."^~ /jellyseerr" = let
        themeParkUrl = "https://theme-park.dev/css/base/overseerr/${nixflix.theme.name}.css";
      in {
        proxyPass = "http://127.0.0.1:${toString cfg.port}";
        recommendedProxySettings = true;
        extraConfig = ''
          # Remove /jellyseerr path to pass to the app
          rewrite ^/jellyseerr/?(.*)$ /$1 break;

          # Redirect location headers
          proxy_redirect ^ /jellyseerr;
          proxy_redirect /setup /jellyseerr/setup;
          proxy_redirect /login /jellyseerr/login;

          # Sub filters to replace hardcoded paths
          proxy_set_header Accept-Encoding "";
          sub_filter_once off;
          sub_filter_types *;
          sub_filter 'href="/"' 'href="/jellyseerr"';
          sub_filter 'href="/login"' 'href="/jellyseerr/login"';
          sub_filter 'href:"/"' 'href:"/jellyseerr"';
          sub_filter '\/_next' '\/jellyseerr\/_next';
          sub_filter '/_next' '/jellyseerr/_next';
          sub_filter '/api/v1' '/jellyseerr/api/v1';
          sub_filter '/login/plex/loading' '/jellyseerr/login/plex/loading';
          sub_filter '/images/' '/jellyseerr/images/';
          sub_filter '/imageproxy/' '/jellyseerr/imageproxy/';
          sub_filter '/avatarproxy/' '/jellyseerr/avatarproxy/';
          sub_filter '/android-' '/jellyseerr/android-';
          sub_filter '/apple-' '/jellyseerr/apple-';
          sub_filter '/favicon' '/jellyseerr/favicon';
          sub_filter '/logo_' '/jellyseerr/logo_';
          sub_filter '/site.webmanifest' '/jellyseerr/site.webmanifest';

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

{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  inherit (import ../../lib/mkVirtualHosts.nix { inherit lib config; }) mkVirtualHost;
  cfg = config.nixflix.droppedneedle;
  hostname = "${cfg.subdomain}.${config.nixflix.reverseProxy.domain}";
in
{
  imports = [
    ./setupService.nix
    ./users
  ];

  options.nixflix.droppedneedle = {
    enable = mkEnableOption "DroppedNeedle music request and discovery app";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ../../pkgs/droppedneedle { };
      defaultText = literalExpression "pkgs.callPackage ../../pkgs/droppedneedle { }";
      description = "DroppedNeedle package to use.";
    };

    user = mkOption {
      type = types.str;
      default = "droppedneedle";
      description = "User under which DroppedNeedle runs.";
    };

    group = mkOption {
      type = types.str;
      default = "media";
      description = "Group under which DroppedNeedle runs.";
    };

    dataDir = mkOption {
      type = types.path;
      default = "${config.nixflix.stateDir}/droppedneedle";
      defaultText = literalExpression ''"''${nixflix.stateDir}/droppedneedle"'';
      description = "Directory containing DroppedNeedle state, cache, config, and library database.";
    };

    port = mkOption {
      type = types.port;
      default = 8688;
      description = "Port on which DroppedNeedle listens.";
    };

    logLevel = mkOption {
      type = types.enum [
        "DEBUG"
        "INFO"
        "WARNING"
        "ERROR"
        "CRITICAL"
      ];
      default = "INFO";
      description = "DroppedNeedle log level.";
    };

    slskd = {
      downloadsPath = mkOption {
        type = types.path;
        default = config.nixflix.slskd.downloadsDir;
        defaultText = literalExpression ''
          if config.nixflix.slskd.enable then config.nixflix.slskd.downloadsDir else null
        '';
        description = "Directory DroppedNeedle imports completed downloads from. ";
      };
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open the DroppedNeedle port in the firewall.";
    };

    subdomain = mkOption {
      type = types.str;
      default = "droppedneedle";
      description = "Subdomain prefix for reverse proxy routing.";
    };

    reverseProxy = {
      expose = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to expose DroppedNeedle via the reverse proxy.";
      };
    };

    vpn = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to route DroppedNeedle traffic through the VPN.

          When `true`, DroppedNeedle is confined to the WireGuard network namespace
          (requires `nixflix.vpn.enable = true`).
        '';
      };
    };

    connectionAddress = mkOption {
      type = types.str;
      readOnly = true;
      default =
        if config.nixflix.vpn.enable && cfg.vpn.enable then
          config.vpnNamespaces.wg.namespaceAddress
        else
          "127.0.0.1";
      description = "Address at which this service is reachable (derived).";
    };
  };

  config = mkIf (config.nixflix.enable && cfg.enable) (mkMerge [
    (mkVirtualHost {
      inherit hostname;
      inherit (cfg.reverseProxy) expose;
      inherit (cfg) port;
      upstreamHost = cfg.connectionAddress;
    })
    {
      assertions = [
        {
          assertion = cfg.vpn.enable -> config.nixflix.vpn.enable;
          message = "nixflix.droppedneedle.vpn.enable = true requires nixflix.vpn.enable = true.";
        }
      ];

      users.users.${cfg.user} = {
        inherit (cfg) group;
        isSystemUser = true;
        home = cfg.dataDir;
      }
      // optionalAttrs (config.nixflix.globals.uids ? ${cfg.user}) {
        uid = mkForce config.nixflix.globals.uids.${cfg.user};
      };

      users.groups.${cfg.group} = optionalAttrs (config.nixflix.globals.gids ? ${cfg.group}) {
        gid = mkForce config.nixflix.globals.gids.media;
      };

      systemd.tmpfiles.settings."10-droppedneedle" = {
        ${cfg.dataDir}.d = {
          mode = "0750";
          inherit (cfg) user group;
        };
        "${cfg.dataDir}/config".d = {
          mode = "0750";
          inherit (cfg) user group;
        };
        "${cfg.dataDir}/cache".d = {
          mode = "0750";
          inherit (cfg) user group;
        };
      };

      systemd.services.droppedneedle = {
        description = "DroppedNeedle music request and discovery app";
        after = [
          "network-online.target"
          "nixflix-setup-dirs.service"
        ]
        ++ optional config.nixflix.slskd.enable "slskd.service"
        ++ config.nixflix.serviceDependencies;
        wants = [ "network-online.target" ];
        requires = [
          "nixflix-setup-dirs.service"
        ]
        ++ config.nixflix.serviceDependencies;
        wantedBy = [ "multi-user.target" ];

        environment = {
          ROOT_APP_DIR = cfg.dataDir;
          DROPPEDNEEDLE_STATIC_DIR = "${cfg.dataDir}/cache/frontend-static";
          PORT = toString cfg.port;
          LOG_LEVEL = cfg.logLevel;
          SLSKD_DOWNLOADS_PATH = cfg.slskd.downloadsPath;
        };

        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          WorkingDirectory = cfg.dataDir;
          ExecStartPre = [
            "${cfg.package}/bin/droppedneedle-configure-frontend-base --static-root ${cfg.dataDir}/cache/frontend-static"
            "${pkgs.writeShellScript "droppedneedle-sync-port" ''
              # config.json's persisted port overrides PORT after first boot; keep ours authoritative.
              CONFIG_FILE="${cfg.dataDir}/config/config.json"
              if [ -f "$CONFIG_FILE" ]; then
                ${pkgs.jq}/bin/jq --argjson port ${toString cfg.port} '.port = $port' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
                mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
              fi
            ''}"
          ];
          ExecStart = getExe cfg.package;
          Restart = "on-failure";
          LimitNOFILE = 65536;

          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [
            cfg.dataDir
            cfg.slskd.downloadsPath
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
        };
      };

      networking.firewall = mkIf cfg.openFirewall {
        allowedTCPPorts = [ cfg.port ];
      };
    }
    (mkIf (config.nixflix.vpn.enable && cfg.vpn.enable) {
      systemd.services.droppedneedle.vpnConfinement = {
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

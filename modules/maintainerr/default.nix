{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  inherit (import ../../lib/mkVirtualHosts.nix { inherit lib config; }) mkVirtualHost;
  cfg = config.nixflix.maintainerr;
  syncMode = import ../../lib/sync-mode.nix { inherit lib pkgs; };
  hostname = "${cfg.subdomain}.${config.nixflix.reverseProxy.domain}";
in
{
  imports = [
    ./forceJellyfinIgnore.nix
    ./overlays
    ./rules
    ./settings
  ];

  options.nixflix.maintainerr = {
    enable = mkEnableOption "Maintainerr media library maintenance tool";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ../../pkgs/maintainerr { };
      defaultText = literalExpression "pkgs.callPackage ../pkgs/maintainerr { }";
      description = "Maintainerr package to use.";
    };

    user = mkOption {
      type = types.str;
      default = "maintainerr";
      description = "User under which Maintainerr runs.";
    };

    group = mkOption {
      type = types.str;
      default = "media";
      description = "Group under which Maintainerr runs.";
    };

    dataDir = mkOption {
      type = types.path;
      default = "${config.nixflix.stateDir}/maintainerr";
      defaultText = literalExpression ''"''${nixflix.stateDir}/maintainerr"'';
      description = "Directory containing Maintainerr state and SQLite database.";
    };

    port = mkOption {
      type = types.port;
      default = 6246;
      description = "Port on which Maintainerr listens.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open the Maintainerr port in the firewall.";
    };

    subdomain = mkOption {
      type = types.str;
      default = "maintainerr";
      description = "Subdomain prefix for reverse proxy routing.";
    };

    reverseProxy = {
      expose = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to expose Maintainerr via the reverse proxy.";
      };
    };

    vpn = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to route Maintainerr traffic through the VPN.

          When `true`, Maintainerr is confined to the WireGuard network namespace
          (requires `nixflix.vpn.enable = true`).
        '';
      };

      namespace = mkOption {
        type = types.str;
        default = config.nixflix.vpn.namespace;
        defaultText = literalExpression "config.nixflix.vpn.namespace";
        description = "Name of the VPN network namespace to confine Maintainerr to when `vpn.enable = true`.";
      };
    };

    syncMode = {
      radarr = syncMode.mkModeOption {
        inherit config;
        what = "Radarr servers";
        collectionOption = "nixflix.maintainerr.settings.radarr";
      };

      sonarr = syncMode.mkModeOption {
        inherit config;
        what = "Sonarr servers";
        collectionOption = "nixflix.maintainerr.settings.sonarr";
      };

      rules = syncMode.mkModeOption {
        inherit config;
        what = "rule groups";
        collectionOption = "nixflix.maintainerr.rules";
      };

      overlayTemplates = syncMode.mkModeOption {
        inherit config;
        what = "overlay templates (presets are never touched)";
        collectionOption = "nixflix.maintainerr.overlays.templates";
      };

      mediaServer = mkOption {
        type = types.enum syncMode.modes;
        default = config.nixflix.syncMode;
        defaultText = literalExpression "config.nixflix.syncMode";
        description = ''
          What `maintainerr-settings` does when Maintainerr is set up for
          another media server (Plex, Emby). Switching it to Jellyfin makes
          Maintainerr clear every rule group and its rules, collection,
          collection media item and log, and exclusion. Defaults to
          `nixflix.syncMode` (`"delete"` unless set); setting this overrides it
          for the switch only.

          - `"delete"`: switch to Jellyfin, clearing that data.
          - `"keep"`: switch only when it clears nothing; otherwise stay on the
            current media server and log what a switch would clear. Staying
            means the Jellyfin connection is not set up, and
            `maintainerr-rules`, which asks Maintainerr which media server it
            uses, skips its rule groups with a log line until Maintainerr is on
            Jellyfin.
          - `"refuse"`: if a switch would clear anything, fail the unit before
            changing anything and list the counts.
        '';
      };
    };

    connectionAddress = mkOption {
      type = types.str;
      readOnly = true;
      default =
        if config.nixflix.vpn.enable && cfg.vpn.enable then
          config.vpnNamespaces.${cfg.vpn.namespace}.namespaceAddress
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
          message = "nixflix.maintainerr.vpn.enable = true requires nixflix.vpn.enable = true.";
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

      systemd.tmpfiles.settings."10-maintainerr" = {
        # 0700: its database holds the Jellyfin and *arr API keys.
        ${cfg.dataDir}.d = {
          mode = "0700";
          inherit (cfg) user group;
        };
      };

      systemd.services.maintainerr = {
        description = "Maintainerr media library maintenance";
        after = [
          "network-online.target"
          "nixflix-setup-dirs.service"
        ]
        ++ config.nixflix.serviceDependencies;
        wants = [ "network-online.target" ];
        requires = [ "nixflix-setup-dirs.service" ] ++ config.nixflix.serviceDependencies;
        wantedBy = [ "multi-user.target" ];

        environment = {
          DATA_DIR = cfg.dataDir;
          UI_PORT = toString cfg.port;
          UI_HOSTNAME =
            if config.nixflix.vpn.enable && cfg.vpn.enable then
              config.vpnNamespaces.${cfg.vpn.namespace}.namespaceAddress
            else
              "127.0.0.1";
          NODE_ENV = "production";
        };

        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          WorkingDirectory = cfg.dataDir;
          ExecStart = "${getExe cfg.package}";
          Restart = "on-failure";

          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [
            cfg.dataDir
            config.nixflix.mediaDir
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

      networking.firewall = mkIf cfg.openFirewall { allowedTCPPorts = [ cfg.port ]; };
    }
    (mkIf (config.nixflix.vpn.enable && cfg.vpn.enable) {
      systemd.services.maintainerr.vpnConfinement = {
        enable = true;
        vpnNamespace = cfg.vpn.namespace;
      };
      vpnNamespaces.${cfg.vpn.namespace}.portMappings = [
        {
          from = cfg.port;
          to = cfg.port;
          protocol = "tcp";
        }
      ];
    })
  ]);
}

{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  inherit (config) nixflix;
  inherit (config.nixflix) globals;
  cfg = config.nixflix.jellyfin;
  hostname = "${cfg.subdomain}.${nixflix.nginx.domain}";

  xml = import ./xml.nix { inherit lib; };

  networkXmlContent = xml.mkXmlContent "NetworkConfiguration" cfg.network;

  waitForApiScript = import ./waitForApiScript.nix {
    inherit pkgs;
    jellyfinCfg = cfg;
  };
in
{
  imports = [
    ./options

    ./apiKeyService.nix
    ./brandingService.nix
    ./encodingService.nix
    ./librariesService.nix
    ./pluginsService.nix
    ./setupWizardService.nix
    ./systemConfigService.nix
    ./usersConfigService.nix
  ];

  config = mkIf (nixflix.enable && cfg.enable) {
    nixflix.jellyfin.libraries = mkMerge [
      (mkIf (nixflix.sonarr.enable or false) {
        Shows = {
          collectionType = "tvshows";
          paths = nixflix.sonarr.mediaDirs;
        };
      })
      (mkIf (nixflix.sonarr-anime.enable or false) {
        Anime = {
          collectionType = "tvshows";
          paths = nixflix.sonarr-anime.mediaDirs;
        };
      })
      (mkIf (nixflix.radarr.enable or false) {
        Movies = {
          collectionType = "movies";
          paths = nixflix.radarr.mediaDirs;
        };
      })
      (mkIf (nixflix.lidarr.enable or false) {
        Music = {
          collectionType = "music";
          paths = nixflix.lidarr.mediaDirs;
        };
      })
    ];

    assertions = [
      {
        assertion = cfg.vpn.enable -> config.nixflix.mullvad.enable;
        message = "Cannot enable VPN routing for Jellyfin (nixflix.jellyfin.vpn.enable = true) when Mullvad VPN is disabled. Please set nixflix.mullvad.enable = true.";
      }
      {
        assertion = any (user: user.policy.isAdministrator) (attrValues cfg.users);
        message = "At least one Jellyfin user must have policy.isAdministrator = true.";
      }
      {
        assertion = cfg.system.cacheSize >= 3;
        message = "nixflix.jellyfin.system.cacheSize must be at least 3 due to Jellyfin's internal caching implementation (got ${toString cfg.system.cacheSize}).";
      }
      {
        assertion = all (p: p.version == null || p.version != "") (attrValues cfg.plugins);
        message = "nixflix.jellyfin.plugins: version must be a non-empty string if specified (use null to install the latest version).";
      }
    ];

    users.users.${cfg.user} = {
      inherit (cfg) group;
      isSystemUser = true;
      home = cfg.dataDir;
      uid = mkForce globals.uids.jellyfin;
    };

    users.groups.${cfg.group} = optionalAttrs (globals.gids ? ${cfg.group}) {
      gid = mkForce globals.gids.${cfg.group};
    };

    systemd.tmpfiles.settings."10-jellyfin" = {
      "${cfg.dataDir}".d = {
        mode = "0755";
        inherit (cfg) user;
        inherit (cfg) group;
      };
      "${cfg.configDir}".d = {
        mode = "0755";
        inherit (cfg) user;
        inherit (cfg) group;
      };
      "${cfg.cacheDir}".d = {
        mode = "0755";
        inherit (cfg) user;
        inherit (cfg) group;
      };
      "${cfg.logDir}".d = {
        mode = "0755";
        inherit (cfg) user;
        inherit (cfg) group;
      };
      "${cfg.system.metadataPath}".d = {
        mode = "0755";
        inherit (cfg) user;
        inherit (cfg) group;
      };
      "${cfg.dataDir}/data".d = {
        mode = "0755";
        inherit (cfg) user;
        inherit (cfg) group;
      };
      "/run/jellyfin".d = {
        mode = "0755";
        inherit (cfg) user;
        inherit (cfg) group;
      };
    };

    environment.etc = {
      "jellyfin/network.xml.template".text = networkXmlContent;
    };

    systemd.services.jellyfin = {
      description = "Jellyfin Media Server";
      after = [
        "network-online.target"
        "nixflix-setup-dirs.service"
      ]
      ++ config.nixflix.serviceDependencies;
      requires = config.nixflix.serviceDependencies;
      wants = [
        "network-online.target"
        "nixflix-setup-dirs.service"
      ];
      wantedBy = [ "multi-user.target" ];

      restartTriggers = [
        networkXmlContent
      ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;
        Restart = "on-failure";
        TimeoutStartSec = 300;
        TimeoutStopSec = 15;
        SuccessExitStatus = "0 143";

        ExecStartPre = pkgs.writeShellScript "jellyfin-setup-config" ''
          set -eu

          ${pkgs.coreutils}/bin/install -m 640 /etc/jellyfin/network.xml.template '${cfg.configDir}/network.xml'
        '';

        ExecStart =
          if (config.nixflix.mullvad.enable && !cfg.vpn.enable) then
            pkgs.writeShellScript "jellyfin-vpn-bypass" ''
              exec /run/wrappers/bin/mullvad-exclude ${getExe cfg.package} \
                --datadir '${cfg.dataDir}' \
                --configdir '${cfg.configDir}' \
                --cachedir '${cfg.cacheDir}' \
                --logdir '${cfg.logDir}'
            ''
          else
            "${getExe cfg.package} --datadir '${cfg.dataDir}' --configdir '${cfg.configDir}' --cachedir '${cfg.cacheDir}' --logdir '${cfg.logDir}'";

        ExecStartPost = waitForApiScript;

        NoNewPrivileges = true;
        LockPersonality = true;

        ProtectControlGroups = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        PrivateTmp = true;

        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
          "AF_NETLINK"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;

        # Needed for hardware acceleration
        PrivateDevices = false;

        PrivateUsers = true;
        RemoveIPC = true;

        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "~@clock"
          "~@aio"
          "~@chown"
          "~@cpu-emulation"
          "~@debug"
          "~@keyring"
          "~@memlock"
          "~@module"
          "~@mount"
          "~@obsolete"
          "~@privileged"
          "~@raw-io"
          "~@reboot"
          "~@setuid"
          "~@swap"
        ];
        SystemCallErrorNumber = "EPERM";
      }
      // optionalAttrs (config.nixflix.mullvad.enable && !cfg.vpn.enable) {
        AmbientCapabilities = "CAP_SYS_ADMIN";
        Delegate = mkForce true;
        SystemCallFilter = mkForce [ ];
        NoNewPrivileges = mkForce false;
        ProtectControlGroups = mkForce false;
      }
      // optionalAttrs cfg.encoding.enableHardwareEncoding {
        SupplementaryGroups = [
          "video"
          "render"
        ];
      };
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [
        cfg.network.internalHttpPort
        cfg.network.internalHttpsPort
      ];
      allowedUDPPorts = [
        1900
        7359
      ];
    };

    networking.hosts = mkIf (nixflix.nginx.enable && nixflix.nginx.addHostsEntries) {
      "127.0.0.1" = [ hostname ];
    };

    services.nginx.virtualHosts."${hostname}" = mkIf nixflix.nginx.enable {
      inherit (config.nixflix.nginx) forceSSL;
      useACMEHost = if config.nixflix.nginx.enableACME then config.nixflix.nginx.domain else null;

      locations = {
        "/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.network.internalHttpPort}";
          recommendedProxySettings = true;
          extraConfig = ''
            proxy_set_header X-Real-IP $remote_addr;

            proxy_buffering off;
          '';
        };
        "/socket" = {
          proxyPass = "http://127.0.0.1:${toString cfg.network.internalHttpPort}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
          extraConfig = ''
            proxy_set_header X-Real-IP $remote_addr;
          '';
        };
      };
    };
  };
}

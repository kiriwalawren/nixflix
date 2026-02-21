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

  baseUrl =
    if cfg.network.baseUrl == "" then
      "http://127.0.0.1:${toString cfg.network.internalHttpPort}"
    else
      "http://127.0.0.1:${toString cfg.network.internalHttpPort}/${cfg.network.baseUrl}";
in
{
  imports = [
    ./options

    ./brandingService.nix
    ./encodingService.nix
    ./librariesService.nix
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
      ];
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
        TimeoutStartSec = 120;
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

        ExecStartPost = pkgs.writeShellScript "jellyfin-wait-ready" ''
          set -eu

          BASE_URL="${baseUrl}"

          echo "Waiting for Jellyfin to finish migrations and be ready..."
          consecutive_success=0
          consecutive_required=5
          for i in {1..240}; do
            HTTP_CODE=$(${pkgs.curl}/bin/curl --connect-timeout 5 --max-time 10 -s -o /dev/null -w "%{http_code}" "$BASE_URL/System/Info/Public" 2>/dev/null || echo "000")

            if [ "$HTTP_CODE" = "200" ]; then
              STARTUP_CODE=$(${pkgs.curl}/bin/curl --connect-timeout 5 --max-time 10 -s -o /dev/null -w "%{http_code}" -X GET "$BASE_URL/Startup/Configuration" 2>/dev/null || echo "000")

              if [ "$STARTUP_CODE" = "200" ] || [ "$STARTUP_CODE" = "204" ] || [ "$STARTUP_CODE" = "401" ]; then
                consecutive_success=$((consecutive_success + 1))
                echo "Jellyfin is ready ($consecutive_success/$consecutive_required consecutive successes)"

                if [ $consecutive_success -ge $consecutive_required ]; then
                  echo "Jellyfin is fully ready (all migrations complete)"
                  exit 0
                fi
              else
                consecutive_success=0
                echo "Jellyfin migrations in progress (System/Info: $HTTP_CODE, Startup: $STARTUP_CODE)... attempt $i/240"
              fi
            else
              consecutive_success=0
              echo "Jellyfin is still starting (HTTP $HTTP_CODE)... attempt $i/240"

              if [ $i -eq 240 ]; then
                echo "Timeout waiting for Jellyfin after 240 attempts (4 minutes)" >&2
                exit 1
              fi
            fi

            sleep 1
          done
        '';

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

{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  inherit (config) nixflix;
  inherit (config.nixflix) globals;
  cfg = config.nixflix.jellyfin;

  xml = import ./xml.nix {inherit lib;};

  networkXmlContent = xml.mkXmlContent "NetworkConfiguration" cfg.network;
  brandingXmlContent = xml.mkXmlContent "BrandingOptions" cfg.branding;
  encodingXmlContent = xml.mkXmlContent "EncodingOptions" cfg.encoding;
in {
  imports = [
    ./options
  ];

  config = mkIf (nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.vpn.enable -> config.nixflix.mullvad.enable;
        message = "Cannot enable VPN routing for Jellyfin (nixflix.jellyfin.vpn.enable = true) when Mullvad VPN is disabled. Please set nixflix.mullvad.enable = true.";
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

    systemd.tmpfiles.rules = [
      "d '${cfg.dataDir}' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.configDir}' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.cacheDir}' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.logDir}' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.system.metadataPath}' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.dataDir}/data' 0750 ${cfg.user} ${cfg.group} - -"
    ];

    environment.etc = {
      "jellyfin/network.xml.template".text = networkXmlContent;
      "jellyfin/branding.xml.template".text = brandingXmlContent;
      "jellyfin/encoding.xml.template".text = encodingXmlContent;
    };

    systemd.services.jellyfin = {
      description = "Jellyfin Media Server";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];

      restartTriggers = [
        networkXmlContent
        brandingXmlContent
        encodingXmlContent
      ];

      serviceConfig =
        {
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
            ${pkgs.coreutils}/bin/install -m 640 /etc/jellyfin/branding.xml.template '${cfg.configDir}/branding.xml'
            ${pkgs.coreutils}/bin/install -m 640 /etc/jellyfin/encoding.xml.template '${cfg.configDir}/encoding.xml'
          '';

          ExecStart =
            if (config.nixflix.mullvad.enable && !cfg.vpn.enable)
            then
              pkgs.writeShellScript "jellyfin-vpn-bypass" ''
                exec /run/wrappers/bin/mullvad-exclude ${getExe cfg.package} \
                  --datadir '${cfg.dataDir}' \
                  --configdir '${cfg.configDir}' \
                  --cachedir '${cfg.cacheDir}' \
                  --logdir '${cfg.logDir}'
              ''
            else "${getExe cfg.package} --datadir '${cfg.dataDir}' --configdir '${cfg.configDir}' --cachedir '${cfg.cacheDir}' --logdir '${cfg.logDir}'";

          NoNewPrivileges = true;
          LockPersonality = true;

          ProtectControlGroups = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          PrivateTmp = true;

          RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK"];
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
          SystemCallFilter = mkForce [];
          NoNewPrivileges = mkForce false;
          ProtectControlGroups = mkForce false;
        };
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [cfg.network.internalHttpPort cfg.network.internalHttpsPort];
      allowedUDPPorts = [1900 7359];
    };

    services.nginx = mkIf nixflix.nginx.enable {
      virtualHosts.localhost.locations = {
        "${cfg.network.baseUrl}" = {
          proxyPass = "http://127.0.0.1:${toString cfg.network.internalHttpPort}";
          recommendedProxySettings = true;
          extraConfig = ''
            proxy_redirect off;

            proxy_set_header X-Real-IP $remote_addr;
            proxy_buffering off;
          '';
        };
        "${cfg.network.baseUrl}/socket" = {
          proxyPass = "http://127.0.0.1:${toString cfg.network.internalHttpPort}";
          recommendedProxySettings = true;
          extraConfig = ''
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
          '';
        };
      };
    };
  };
}

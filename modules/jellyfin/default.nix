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

  waitForApiScript = import ./waitForApiScript.nix {
    inherit pkgs;
    jellyfinCfg = cfg;
  };
in
{
  imports = [
    ./branding
    ./encoding
    ./libaries
    ./metadata
    ./network
    ./options.nix
    ./plugins
    ./system
    ./users

    ./apiKeyService.nix
    ./setupWizardService.nix
  ];

  config = mkIf (nixflix.enable && cfg.enable) {
    assertions = [
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
    }
    // optionalAttrs (config.nixflix.globals.uids ? ${cfg.user}) {
      uid = mkForce config.nixflix.globals.uids.${cfg.user};
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

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;
        Restart = "on-failure";
        TimeoutStartSec = 300;
        TimeoutStopSec = 15;
        SuccessExitStatus = "0 143";

        ExecStart = "${getExe cfg.package} --datadir '${cfg.dataDir}' --configdir '${cfg.configDir}' --cachedir '${cfg.cacheDir}' --logdir '${cfg.logDir}'";

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
      // optionalAttrs cfg.encoding.enableHardwareEncoding {
        SupplementaryGroups = [
          "video"
          "render"
        ];
      };
    };
  };
}

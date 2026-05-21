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

  jellyfinPlugins = import ../../lib/jellyfin-plugins.nix { inherit lib; };

  waitForApiScript = import ./waitForApiScript.nix {
    inherit pkgs;
    jellyfinCfg = cfg;
  };

  pluginResolution = import ./plugins/resolvePlugins.nix {
    inherit lib pkgs;
    jellyfinVersion = cfg.package.version;
    inherit (cfg.system) pluginRepositories;
    inherit (cfg) plugins;
  };

  enabledPlugins = pluginResolution.resolvedEnabledPlugins;

  configuredEnabledPlugins = filterAttrs (_name: pluginCfg: pluginCfg.enable) cfg.plugins;

  inherit (pluginResolution) packagePluginDirName;

  packagePluginDirNames = mapAttrsToList (_name: pluginCfg: packagePluginDirName pluginCfg.package) (
    filterAttrs (_name: pluginCfg: pluginCfg.package != null) enabledPlugins
  );
in
{
  imports = [
    ./branding
    ./encoding
    ./libaries
    ./network
    ./options.nix
    ./plugins
    ./system
    ./users

    ./apiKeyService.nix
    ./setupWizardService.nix
  ];

  config = mkIf (nixflix.enable && cfg.enable) {
    warnings = pluginResolution.resolutionWarnings;

    nixflix.jellyfin = {
      plugins.AniDB = mkIf config.nixflix.sonarr-anime.enable {
        package = mkDefault (
          jellyfinPlugins.fromRepo {
            version = "11.0.0.0";
            hash = "sha256-Rtvxq6NxQSrRyhYdsyWXY+SoDPW4S0471gmiLTUjaSk=";
          }
        );
        config = {
          TitlePreference = mkDefault "Localized";
          OriginalTitlePreference = mkDefault "JapaneseRomaji";
          IgnoreSeason = mkDefault false;
          TitleSimilarityThreshold = mkDefault "50";
          MaxGenres = mkDefault "5";
          TidyGenreList = mkDefault true;
          TitleCaseGenres = mkDefault false;
          AnimeDefaultGenre = mkDefault "Anime";
          AniDbRateLimit = mkDefault "2000";
          MaxCacheAge = mkDefault "7";
          AniDbReplaceGraves = mkDefault true;
        };
      };
    };

    assertions = [
      {
        assertion = any (user: user.policy.isAdministrator) (attrValues cfg.users);
        message = "At least one Jellyfin user must have policy.isAdministrator = true.";
      }
      {
        assertion = cfg.system.cacheSize >= 3;
        message = "nixflix.jellyfin.system.cacheSize must be at least 3 due to Jellyfin's internal caching implementation (got ${toString cfg.system.cacheSize}).";
      }
      {
        assertion = all (pluginCfg: pluginCfg.package != null) (attrValues configuredEnabledPlugins);
        message = "nixflix.jellyfin.plugins: enabled plugins must define `package`. Use `nixflix.lib.jellyfinPlugins.fromRepo` for repository-backed plugins.";
      }
      {
        assertion = length packagePluginDirNames == length (unique packagePluginDirNames);
        message = "nixflix.jellyfin.plugins contains duplicate package-managed plugin directory names.";
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

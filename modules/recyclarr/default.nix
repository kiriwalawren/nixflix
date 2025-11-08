{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  inherit (config) nixflix;
  inherit (config.nixflix) globals;
  cfg = config.nixflix.recyclarr;

  configOption = import ./config-option.nix {inherit lib;};

  radarrApiWait = import ../arr-common/mkWaitForApiScript.nix {inherit lib pkgs;} "radarr" nixflix.radarr;
  sonarrApiWait = import ../arr-common/mkWaitForApiScript.nix {inherit lib pkgs;} "sonarr" nixflix.sonarr;

  sonarrConfig = optionalAttrs cfg.sonarr.enable (import ./sonarr-default.nix {inherit config lib;});
  radarrConfig = optionalAttrs cfg.radarr.enable (import ./radarr-default.nix {inherit config lib;});
  effectiveConfiguration =
    if cfg.config == null
    then sonarrConfig // radarrConfig
    else cfg.config;

  cleanupProfilesServices = import ./cleanup-profiles.nix {
    inherit config lib pkgs;
    recyclarrConfig = effectiveConfiguration;
  };
in {
  options.nixflix.recyclarr = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to enable Recyclarr for automated TRaSH guide syncing";
    };

    user = mkOption {
      type = types.str;
      default = "recyclarr";
      description = "User under which Recyclarr runs";
    };

    group = mkOption {
      type = types.str;
      default = "recyclarr";
      description = "Group under which Recyclarr runs";
    };

    sonarr = {
      enable = mkOption {
        type = types.bool;
        default = config.nixflix.sonarr.enable;
        defaultText = literalExpression "config.nixflix.sonarr.enable";
        description = "Whether to sync Sonarr configuration via Recyclarr";
      };

      anime = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Whether to enable anime-specific profiles for Sonarr.
            When enabled, BOTH normal and anime quality profiles will be configured,
            following TRaSH Guides' recommendation for single-instance setups.
          '';
        };
      };
    };

    radarr = {
      enable = mkOption {
        type = types.bool;
        default = config.nixflix.radarr.enable;
        defaultText = literalExpression "config.nixflix.radarr.enable";
        description = "Whether to sync Radarr configuration via Recyclarr";
      };

      anime = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Whether to enable anime-specific profiles for Radarr.
            When enabled, BOTH normal and anime quality profiles will be configured,
            following TRaSH Guides' recommendation for single-instance setups.
          '';
        };
      };
    };

    cleanupUnmanagedProfiles = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to automatically remove quality profiles from Sonarr and Radarr
        that are not managed by Recyclarr.

        Only removes profiles from instances matching nixflix.sonarr and nixflix.radarr
        base URLs, and only when quality_profiles is defined in the Recyclarr configuration.

        Any series/movies using unmanaged profiles will be reassigned to the first
        managed profile before deletion.
      '';
    };

    config = configOption;
  };

  config = mkIf (nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.sonarr.enable || cfg.radarr.enable;
        message = "Recyclarr requires at least one of nixflix.recyclarr.sonarr.enable or nixflix.recyclarr.radarr.enable to be true";
      }
      {
        assertion = cfg.sonarr.enable -> config.nixflix.sonarr.config.apiKeyPath != null;
        message = "Recyclarr Sonarr sync requires nixflix.sonarr.config.apiKeyPath to be set";
      }
      {
        assertion = cfg.radarr.enable -> config.nixflix.radarr.config.apiKeyPath != null;
        message = "Recyclarr Radarr sync requires nixflix.radarr.config.apiKeyPath to be set";
      }
    ];

    users.users.${cfg.user} = optionalAttrs (globals.uids ? ${cfg.user}) {
      uid = mkForce globals.uids.${cfg.user};
    };

    users.groups.${cfg.group} = optionalAttrs (globals.gids ? ${cfg.group}) {
      gid = mkForce globals.gids.${cfg.group};
    };

    services.recyclarr = {
      enable = true;
      inherit (cfg) user group;
      configuration = effectiveConfiguration;
      schedule = "daily";
    };

    systemd.services =
      {
        recyclarr = {
          after =
            ["nixflix-setup-dirs.service" "network-online.target"]
            ++ optional cfg.radarr.enable "radarr-config.service"
            ++ optional cfg.sonarr.enable "sonarr-config.service";
          requires =
            optional cfg.radarr.enable "radarr-config.service"
            ++ optional cfg.sonarr.enable "sonarr-config.service";
          wants = ["network-online.target"];
          wantedBy = mkForce ["multi-user.target"];

          serviceConfig = {
            LoadCredential =
              optional cfg.radarr.enable "radarr-api_key:${config.nixflix.radarr.config.apiKeyPath}"
              ++ optional cfg.sonarr.enable "sonarr-api_key:${config.nixflix.sonarr.config.apiKeyPath}";
            ExecStartPre = ''
              ${radarrApiWait}
              ${sonarrApiWait}
            '';
          };
        };
      }
      // cleanupProfilesServices;
  };
}

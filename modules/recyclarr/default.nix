{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  inherit (config) nixflix;
  inherit (nixflix) globals;
  cfg = nixflix.recyclarr;

  configOption = import ./config-option.nix {inherit lib;};

  sonarrMainConfig = optionalAttrs cfg.sonarr.enable (import ./sonarr-main.nix {inherit config;});
  sonarrAnimeConfig = optionalAttrs cfg.sonarr-anime.enable (import ./sonarr-anime.nix {inherit config;});
  radarrMainConfig = optionalAttrs cfg.radarr.enable (import ./radarr-main.nix {inherit config;});
  effectiveConfiguration =
    if cfg.config == null
    then {
      radarr = radarrMainConfig;
      sonarr =
        sonarrMainConfig
        // optionalAttrs cfg.sonarr-anime.enable sonarrAnimeConfig;
    }
    else cfg.config;

  cleanupProfilesServices = import ./cleanup-profiles.nix {
    inherit config lib pkgs;
    recyclarrConfig = effectiveConfiguration;
  };
in {
  options.nixflix.recyclarr = {
    enable = mkOption {
      type = types.bool;
      default = nixflix.radarr.enable or nixflix.sonarr.enable or nixflix.sonarr-anime.enable;
      defaultText = literalExpression "nixflix.radarr.enable or nixflix.sonarr.enable or nixflix.sonarr-anime.enable";
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
        default = nixflix.sonarr.enable;
        defaultText = literalExpression "nixflix.sonarr.enable";
        description = "Whether to sync Sonarr configuration via Recyclarr";
      };
    };

    sonarr-anime = {
      enable = mkOption {
        type = types.bool;
        default = nixflix.sonarr-anime.enable;
        description = ''
          Whether to enable anime-specific profiles for Sonarr.
          When enabled, BOTH normal and anime quality profiles will be configured,
          following TRaSH Guides' recommendation for single-instance setups.
        '';
      };
    };

    radarr = {
      enable = mkOption {
        type = types.bool;
        default = nixflix.radarr.enable;
        defaultText = literalExpression "nixflix.radarr.enable";
        description = "Whether to sync Radarr configuration via Recyclarr";
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
        assertion = cfg.sonarr.enable -> nixflix.sonarr.config.apiKey != null;
        message = "Recyclarr Sonarr sync requires nixflix.sonarr.config.apiKey to be set";
      }
      {
        assertion = cfg.radarr.enable -> nixflix.radarr.config.apiKey != null;
        message = "Recyclarr Radarr sync requires nixflix.radarr.config.apiKey to be set";
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
            ["network-online.target"]
            ++ optional cfg.radarr.enable "radarr-config.service"
            ++ optional cfg.sonarr.enable "sonarr-config.service"
            ++ optional cfg.sonarr-anime.enable "sonarr-anime-config.service";
          requires =
            optional cfg.radarr.enable "radarr-config.service"
            ++ optional cfg.sonarr.enable "sonarr-config.service"
            ++ optional cfg.sonarr-anime.enable "sonarr-anime-config.service";
          wants = ["network-online.target"];
          wantedBy = mkForce ["multi-user.target"];
        };
      }
      // cleanupProfilesServices;
  };
}

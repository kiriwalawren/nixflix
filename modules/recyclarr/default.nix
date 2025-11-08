{
  config,
  lib,
  ...
}:
with lib; let
  inherit (config) nixflix;
  inherit (config.nixflix) globals;
  cfg = config.nixflix.recyclarr;

  configOption = import ./config-option.nix {inherit lib;};

  sonarrConfig = optionalAttrs cfg.sonarr.enable (import ./sonarr-default.nix {inherit config lib;});
  radarrConfig = optionalAttrs cfg.radarr.enable (import ./radarr-default.nix {inherit config lib;});
  effectiveConfiguration =
    if cfg.config == null
    then sonarrConfig // radarrConfig
    else cfg.config;
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

    systemd.services.recyclarr = {
      after =
        ["nixflix-setup-dirs.service" "network-online.target"]
        ++ optional cfg.radarr.enable "radarr-config.service"
        ++ optional cfg.sonarr.enable "sonarr-config.service";
      requires =
        optional cfg.radarr.enable "radarr-config.service"
        ++ optional cfg.sonarr.enable "sonarr-config.service";
      wants = ["network-online.target"];
      wantedBy = mkForce ["multi-user.target"]; # Run on startup

      serviceConfig.LoadCredential =
        optional cfg.radarr.enable "radarr-api_key:${config.nixflix.radarr.config.apiKeyPath}"
        ++ optional cfg.sonarr.enable "sonarr-api_key:${config.nixflix.sonarr.config.apiKeyPath}";
    };
  };
}

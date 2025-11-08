{
  config,
  lib,
  ...
}:
with lib; let
  inherit (config) nixflix;
  inherit (config.nixflix) globals;
  cfg = config.nixflix.recyclarr;

  sonarrConfig = optionalAttrs cfg.sonarr.enable {
    sonarr = {
      sonarr_main = {
        base_url = "http://127.0.0.1:${toString config.nixflix.sonarr.config.hostConfig.port}${toString config.nixflix.sonarr.config.hostConfig.urlBase}";
        api_key._secret = "/run/credentials/recyclarr.service/sonarr-api_key";
        media_naming = {
          series = "default";
          season = "default";
          episodes = {
            rename = true;
            standard = "default";
            daily = "default";
            anime = "default";
          };
        };

        include =
          [
            {template = "sonarr-quality-definition-series";}
            {template = "sonarr-v4-quality-profile-web-2160p-alternative";}
            {template = "sonarr-v4-custom-formats-web-2160p";}
          ]
          ++ optionals cfg.sonarr.anime.enable [
            {template = "sonarr-quality-definition-anime";}
            {template = "sonarr-v4-quality-profile-anime";}
            {template = "sonarr-v4-custom-formats-anime";}
          ];
      };
    };
  };

  radarrConfig = optionalAttrs cfg.radarr.enable {
    radarr = {
      radarr_main = {
        base_url = "http://127.0.0.1:${toString config.nixflix.radarr.config.hostConfig.port}${toString config.nixflix.radarr.config.hostConfig.urlBase}";
        api_key._secret = "/run/credentials/recyclarr.service/radarr-api_key";
        media_naming = {
          folder = "default";
          movie = {
            rename = true;
            standard = "standard";
          };
        };

        quality_profiles = [
          {
            name = "UHD Bluray + WEB";
            reset_unmatched_scores.enabled = true;
            upgrade = {
              allowed = true;
              until_quality = "Bluray-2160p";
              until_score = 10000;
            };
            min_format_score = 0;
            quality_sort = "top";
            qualities = [
              {name = "Bluray-2160p";}
              {
                name = "WEB-2160p";
                qualities = ["WEBDL-2160p" "WEBRip-2160p"];
              }
              {name = "Bluray-1080p";}
              {
                name = "WEB-1080p";
                qualities = ["WEBDL-1080p" "WEBRip-1080p"];
              }
              {name = "Bluray-720p";}
            ];
          }
        ];

        include =
          [
            {template = "radarr-quality-definition-movie";}
            {template = "radarr-quality-profile-sqp-1-2160p-default";}
            {template = "radarr-custom-formats-uhd-bluray-web";}
          ]
          ++ optionals cfg.radarr.anime.enable [
            {template = "radarr-quality-definition-anime";}
            {template = "radarr-quality-profile-anime";}
            {template = "radarr-custom-formats-anime";}
          ];
      };
    };
  };

  recyclarrConfiguration = sonarrConfig // radarrConfig;
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

    config = mkOption {
      type = types.nullOr types.attrs;
      default = null;
      description = ''
        Recyclarr configuration as a Nix attribute set.
        When set, this completely replaces the auto-generated configuration,
        giving you full control over the Recyclarr setup.
      '';
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
      configuration =
        if cfg.config == null
        then recyclarrConfiguration
        else cfg.config;
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

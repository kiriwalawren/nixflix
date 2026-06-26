{
  config,
  lib,
  ...
}:
let
  secrets = import ../../../lib/secrets { inherit lib; };

  mkArrSubmodule =
    name:
    lib.types.submodule {
      options = {
        serverName = lib.mkOption {
          type = lib.types.str;
          description = "Display name of the ${name} server.";
        };

        url = lib.mkOption {
          type = lib.types.str;
          description = "URL of the ${name} server.";
          example = "http://localhost:7878";
        };

        apiKey = secrets.mkSecretOption {
          description = "API Key for ${name} server";
        };
      };
    };

in
{
  options.nixflix.maintainerr.settings = {
    forceJellyfinToIgnoreEmptyMediaFolders = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Forces jellyfin to ignore shows where all media files have been
        removed but the folder itself still exists.

        This likely represents the case of shows that have been entirely
        watched and deleted, but are still monitored for future episodes by Sonarr.
      '';
    };

    jellyfin = {
      jellyfin_url = lib.mkOption {
        type = lib.types.str;
        default = "http://${config.nixflix.jellyfin.connectionAddress}:${builtins.toString config.nixflix.jellyfin.network.internalHttpPort}";
        defaultText = lib.literalExpression ''"http://''${config.nixflix.jellyfin.connectionAddress}:''${config.nixflix.jellyfin.port}"'';
        description = "URL to access Jellyfin";
      };

      jellyfin_api_key = secrets.mkSecretOption {
        default = config.nixflix.jellyfin.apiKey;
        description = "API Key for Jellyfin";
      };
    };

    seerr = {
      url = lib.mkOption {
        type = lib.types.str;
        default = "http://${config.nixflix.seerr.connectionAddress}:${builtins.toString config.nixflix.seerr.port}";
        defaultText = lib.literalExpression ''"http://''${config.nixflix.seerr.connectionAddress}:''${config.nixflix.seerr.port}"'';
        description = "URL to access Seerr.";
      };

      api_key = secrets.mkSecretOption {
        default = config.nixflix.seerr.apiKey;
        description = "API Key for Seerr.";
      };
    };

    radarr = lib.mkOption {
      type = lib.types.listOf (mkArrSubmodule "Radarr");
    };

    sonarr = lib.mkOption {
      type = lib.types.listOf (mkArrSubmodule "Sonarr");
    };

    jobs = {
      collection_handler_job_cron = lib.mkOption {
        type = lib.types.str;
        default = "0 0-23/12 * * *";
        description = "Cron schedule for the collection handler job.";
        example = "0 4 * * *";
      };

      rules_handler_job_cron = lib.mkOption {
        type = lib.types.str;
        default = "0 0-23/8 * * *";
        description = "Cron schedule for the rules handler job.";
        example = "0 */4 * * *";
      };
    };
  };

  config.nixflix.maintainerr.settings = {
    radarr = lib.optional (config.nixflix.radarr.enable == true) {
      serverName = "Radarr";
      url = "http://${config.nixflix.radarr.connectionAddress}:${builtins.toString config.nixflix.radarr.config.hostConfig.port}";
      apiKey = config.nixflix.radarr.config.apiKey;
    };
    sonarr =
      lib.optional (config.nixflix.sonarr.enable == true) {
        serverName = "Sonarr";
        url = "http://${config.nixflix.sonarr.connectionAddress}:${builtins.toString config.nixflix.sonarr.config.hostConfig.port}";
        apiKey = config.nixflix.sonarr.config.apiKey;
      }
      ++ lib.optional (config.nixflix.sonarr-anime.enable == true) {
        serverName = "Sonarr Anime";
        url = "http://${config.nixflix.sonarr-anime.connectionAddress}:${builtins.toString config.nixflix.sonarr-anime.config.hostConfig.port}";
        apiKey = config.nixflix.sonarr-anime.config.apiKey;
      };
  };
}

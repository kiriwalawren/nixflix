{
  config,
  lib,
  ...
}:
with lib;
let
  secrets = import ../../../lib/secrets { inherit lib; };

  sonarrServerModule = types.submodule (
    { config, ... }:
    {
      options = {
        hostname = mkOption {
          type = types.str;
          default = "127.0.0.1";
          description = "Sonarr hostname";
        };

        port = mkOption {
          type = types.port;
          default = 8989;
          description = "Sonarr port";
        };

        apiKey = secrets.mkSecretOption {
          description = "Sonarr API key.";
        };

        useSsl = mkOption {
          type = types.bool;
          default = false;
          description = "Use SSL to connect to Sonarr";
        };

        baseUrl = mkOption {
          type = types.str;
          default = "";
          example = "/sonarr";
          description = "Sonarr URL base";
        };

        activeProfileName = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Quality profile name. Defaults to first available quality profile in Seerr.";
        };

        activeDirectory = mkOption {
          type = types.str;
          default = head (config.nixflix.sonarr.mediaDirs or [ "/tv" ]);
          defaultText = literalExpression ''head (config.nixflix.sonarr.mediaDirs or ["/tv"])'';
          description = "Root folder for TV shows";
        };

        activeAnimeProfileName = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Anime quality profile name.";
        };

        activeAnimeDirectory = mkOption {
          type = types.str;
          default = "";
          description = "Root folder for anime";
        };

        seriesType = mkOption {
          type = types.enum [
            "standard"
            "daily"
          ];
          default = "standard";
          description = "Series type for regular content";
        };

        animeSeriesType = mkOption {
          type = types.enum [
            "standard"
            "anime"
          ];
          default = "standard";
          description = "Series type for anime content";
        };

        enableSeasonFolders = mkOption {
          type = types.bool;
          default = true;
          description = "Enable season folders";
        };

        is4k = mkOption {
          type = types.bool;
          default = false;
          description = "Is this a 4K Sonarr instance";
        };

        isDefault = mkOption {
          type = types.bool;
          default = false;
          description = "Is this the default Sonarr instance";
        };

        externalUrl = mkOption {
          type = types.str;
          default = "";
          description = "External URL for Sonarr";
        };

        syncEnabled = mkOption {
          type = types.bool;
          default = false;
          description = "Enable automatic sync with Sonarr";
        };

        preventSearch = mkOption {
          type = types.bool;
          default = false;
          description = "Prevent Seerr from triggering searches";
        };
      };
    }
  );

  defaultInstances =
    (optionalAttrs (config.nixflix.sonarr.enable or false) {
      Sonarr = {
        hostname = config.nixflix.sonarr.config.hostConfig.bindAddress;
        port = config.nixflix.sonarr.config.hostConfig.port or 8989;
        inherit (config.nixflix.sonarr.config) apiKey;
        baseUrl = config.nixflix.sonarr.config.hostConfig.urlBase;
        activeDirectory = head (config.nixflix.sonarr.mediaDirs or [ "/data/media/tv" ]);
        activeAnimeDirectory = head (config.nixflix.sonarr.mediaDirs or [ "/data/media/tv" ]);
        seriesType = "standard";
        animeSeriesType = "standard";
        isDefault = true;
        externalUrl =
          if config.nixflix.reverseProxy.enable then
            "${config.nixflix.seerr.externalUrlScheme}://${config.nixflix.sonarr.subdomain}.${config.nixflix.reverseProxy.domain}${config.nixflix.sonarr.config.hostConfig.urlBase}"
          else
            "";
      };
    })
    // (optionalAttrs (config.nixflix.sonarr-anime.enable or false) {
      "Sonarr Anime" = {
        hostname = config.nixflix.sonarr-anime.config.hostConfig.bindAddress;
        port = config.nixflix.sonarr-anime.config.hostConfig.port or 8990;
        inherit (config.nixflix.sonarr-anime.config) apiKey;
        baseUrl = config.nixflix.sonarr-anime.config.hostConfig.urlBase;
        activeDirectory = head (config.nixflix.sonarr-anime.mediaDirs or [ "/data/media/anime" ]);
        activeAnimeDirectory = head (config.nixflix.sonarr-anime.mediaDirs or [ "/data/media/anime" ]);
        seriesType = "standard";
        animeSeriesType = "anime";
        isDefault = false;
        externalUrl =
          if config.nixflix.reverseProxy.enable then
            "${config.nixflix.seerr.externalUrlScheme}://${config.nixflix.sonarr-anime.subdomain}.${config.nixflix.reverseProxy.domain}${config.nixflix.sonarr-anime.config.hostConfig.urlBase}"
          else
            "";
      };
    });
in
{
  options.nixflix.seerr.sonarr = mkOption {
    type = types.attrsOf sonarrServerModule;
    default = defaultInstances;
    description = ''
      Sonarr instances to configure. Automatically configured from `config.nixflix.sonarr` and `config.nixflix.sonarr-anime` when enabled, otherwise `{}`.

      Default instances can be overridden with `lib.mkForce {}`.
    '';
    example = {
      Sonarr = {
        port = 8989;
        activeProfileName = "WEB-1080p";
        activeDirectory = "/tv";
      };
      "Sonarr Anime" = {
        port = 8990;
        activeProfileName = "Remux-1080p - Anime";
        activeDirectory = "/anime";
      };
    };
  };
}

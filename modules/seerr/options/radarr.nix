{
  config,
  lib,
  ...
}:
with lib;
let
  secrets = import ../../../lib/secrets { inherit lib; };

  radarrServerModule = types.submodule {
    options = {
      hostname = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Radarr hostname";
      };

      port = mkOption {
        type = types.port;
        default = 7878;
        description = "Radarr port";
      };

      apiKey = secrets.mkSecretOption {
        description = "Radarr API key.";
      };

      useSsl = mkOption {
        type = types.bool;
        default = false;
        description = "Use SSL to connect to Radarr";
      };

      baseUrl = mkOption {
        type = types.str;
        default = "";
        example = "/radarr";
        description = "Radarr URL base";
      };

      activeProfileName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Quality profile name. Defaults to first available quality profile in Seerr.";
      };

      activeDirectory = mkOption {
        type = types.str;
        default = head (config.nixflix.radarr.mediaDirs or [ "/movies" ]);
        defaultText = literalExpression ''head (config.nixflix.radarr.mediaDirs or ["/movies"])'';
        description = "Root folder for movies";
      };

      is4k = mkOption {
        type = types.bool;
        default = false;
        description = "Is this a 4K Radarr instance";
      };

      minimumAvailability = mkOption {
        type = types.enum [
          "announced"
          "inCinemas"
          "released"
        ];
        default = "released";
        description = "Minimum availability for movies";
      };

      isDefault = mkOption {
        type = types.bool;
        default = false;
        description = "Is this the default Radarr instance";
      };

      externalUrl = mkOption {
        type = types.str;
        default = "";
        description = "External URL for Radarr";
      };

      syncEnabled = mkOption {
        type = types.bool;
        default = false;
        description = "Enable automatic sync with Radarr";
      };

      preventSearch = mkOption {
        type = types.bool;
        default = false;
        description = "Prevent Seerr from triggering searches";
      };
    };
  };

  defaultInstance = optionalAttrs (config.nixflix.radarr.enable or false) {
    Radarr = {
      port = config.nixflix.radarr.config.hostConfig.port or 7878;
      inherit (config.nixflix.radarr.config) apiKey;
      baseUrl = config.nixflix.radarr.config.hostConfig.urlBase;
      activeDirectory = head (config.nixflix.radarr.mediaDirs or [ "/data/media/movies" ]);
      isDefault = true;
      externalUrl =
        if config.nixflix.nginx.enable then
          "${config.nixflix.seerr.externalUrlScheme}://${config.nixflix.radarr.subdomain}.${config.nixflix.nginx.domain}${config.nixflix.radarr.config.hostConfig.urlBase}"
        else
          "";
    };
  };
in
{
  options.nixflix.seerr.radarr = mkOption {
    type = types.attrsOf radarrServerModule;
    default = defaultInstance;
    description = ''
      Radarr instances to configure. Automatically configured from `config.nixflix.radarr` when enabled, otherwise `{}`.

      Default instances can be overridden with `lib.mkForce {}`.
    '';
    example = {
      Radarr = {
        apiKey = {
          _secret = "/run/secrets/radarr-apikey";
        };
        activeProfileName = "HD-1080p";
        activeDirectory = "/movies";
      };
      "Radarr 4K" = {
        apiKey = {
          _secret = "/run/secrets/radarr-4k-apikey";
        };
        activeProfileName = "UHD-2160p";
        activeDirectory = "/movies-4k";
        is4k = true;
      };
    };
  };
}

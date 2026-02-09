{
  config,
  lib,
  ...
}:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  radarrRecyclarrConfig = optionalAttrs (config.nixflix.recyclarr.radarr.enable or false) (
    import ../../recyclarr/radarr-main.nix { inherit config; }
  );
  firstRadarrProfile = head (radarrRecyclarrConfig.radarr_main.quality_profiles or [ ]);
  defaultRadarrProfileName =
    if config.nixflix.recyclarr.enable then firstRadarrProfile.name else null;

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
        default = defaultRadarrProfileName;
        defaultText = literalExpression ''
          if config.nixflix.recyclarr.radarr.enable
          then (head (import ../../recyclarr/radarr-main.nix {inherit config;}).radarr_main.quality_profiles).name
          else null
        '';
        description = "Quality profile name. Defaults to first recyclarr quality profile if enabled.";
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
        description = "Prevent Jellyseerr from triggering searches";
      };
    };
  };

  defaultInstance = optionalAttrs (config.nixflix.radarr.enable or false) {
    Radarr = {
      port = config.nixflix.radarr.config.hostConfig.port or 7878;
      inherit (config.nixflix.radarr.config) apiKey;
      baseUrl =
        if config.nixflix.nginx.enable then config.nixflix.radarr.config.hostConfig.urlBase else "";
      activeProfileName = defaultRadarrProfileName;
      activeDirectory = head (config.nixflix.radarr.mediaDirs or [ "/data/media/movies" ]);
      isDefault = true;
      externalUrl =
        if config.nixflix.jellyseerr.externalBaseUrl != "" then
          "${config.nixflix.jellyseerr.externalBaseUrl}${config.nixflix.radarr.config.hostConfig.urlBase}"
        else
          "";
    };
  };
in
{
  options.nixflix.jellyseerr.radarr = mkOption {
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

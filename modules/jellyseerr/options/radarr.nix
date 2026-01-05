{
  config,
  lib,
  ...
}:
with lib; let
  radarrRecyclarrConfig =
    optionalAttrs (config.nixflix.recyclarr.radarr.enable or false)
    (import ../../recyclarr/radarr-main.nix {inherit config;});
  firstRadarrProfile = head (radarrRecyclarrConfig.radarr_main.quality_profiles or []);
  defaultRadarrProfileName = firstRadarrProfile.name or null;

  radarrServerModule = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        default = "Radarr";
        description = "Display name for this Radarr instance";
      };

      hostname = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Radarr hostname";
      };

      port = mkOption {
        type = types.port;
        default = config.nixflix.radarr.config.hostConfig.port or 7878;
        defaultText = literalExpression "config.nixflix.radarr.config.hostConfig.port";
        description = "Radarr port";
      };

      apiKeyPath = mkOption {
        type = types.path;
        description = "Path to file containing Radarr API key";
      };

      useSsl = mkOption {
        type = types.bool;
        default = false;
        description = "Use SSL to connect to Radarr";
      };

      baseUrl = mkOption {
        type = types.str;
        default =
          if config.nixflix.nginx.enable
          then "/radarr"
          else "";
        defaultText = literalExpression ''if config.nixflix.nginx.enable then "/radarr" else ""'';
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
        default = head (config.nixflix.radarr.mediaDirs or ["/movies"]);
        defaultText = literalExpression ''head (config.nixflix.radarr.mediaDirs or ["/movies"])'';
        description = "Root folder for movies";
      };

      is4k = mkOption {
        type = types.bool;
        default = false;
        description = "Is this a 4K Radarr instance";
      };

      minimumAvailability = mkOption {
        type = types.enum ["announced" "inCinemas" "released"];
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

  defaultInstance =
    if (config.nixflix.radarr.enable or false)
    then [
      {
        name = "Radarr";
        port = config.nixflix.radarr.config.hostConfig.port or 7878;
        inherit (config.nixflix.radarr.config) apiKeyPath;
        baseUrl =
          if config.nixflix.nginx.enable
          then "/radarr"
          else "";
        activeProfileName = defaultRadarrProfileName;
        activeDirectory = head (config.nixflix.radarr.mediaDirs or ["/data/media/movies"]);
        isDefault = true;
      }
    ]
    else [];
in {
  options.nixflix.jellyseerr.radarr = mkOption {
    type = types.listOf radarrServerModule;
    default = defaultInstance;
    description = ''
      List of Radarr instances to configure.

      Automatically configured from `config.nixflix.radarr` when enabled, otherwise `[]`.
    '';
    example = [
      {
        name = "Radarr Main";
        apiKeyPath = "/run/secrets/radarr-apikey";
        activeProfileName = "HD-1080p";
        activeDirectory = "/movies";
      }
    ];
  };
}

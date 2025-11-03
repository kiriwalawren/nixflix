{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  mkProwlarrIndexersService = import ./indexersService.nix {inherit lib pkgs;};
  mkProwlarrApplicationsService = import ./applicationsService.nix {inherit lib pkgs;};
  arrCommon = import ../arr-common {
    inherit config lib pkgs;
  };

  # List of arr services that can be auto-configured as applications
  arrServices = ["lidarr" "radarr" "sonarr"];

  # Helper to create default application config for an enabled service
  mkDefaultApplication = serviceName: let
    serviceConfig = config.nixflix.${serviceName}.config;
    capitalizedName = lib.toUpper (builtins.substring 0 1 serviceName) + builtins.substring 1 (-1) serviceName;
    useNginx = config.nixflix.nginx.enable or false;
    baseUrl =
      if useNginx
      then "http://127.0.0.1${serviceConfig.hostConfig.urlBase}"
      else "http://127.0.0.1:${toString serviceConfig.hostConfig.port}${serviceConfig.hostConfig.urlBase}";
    prowlarrUrl =
      if useNginx
      then "http://127.0.0.1${config.nixflix.prowlarr.config.hostConfig.urlBase}"
      else "http://127.0.0.1:${toString config.nixflix.prowlarr.config.hostConfig.port}${config.nixflix.prowlarr.config.hostConfig.urlBase}";
  in
    mkIf (config.nixflix.${serviceName}.enable or false) {
      name = capitalizedName;
      implementationName = capitalizedName;
      apiKeyPath = mkDefault serviceConfig.apiKeyPath;
      baseUrl = mkDefault baseUrl;
      prowlarrUrl = mkDefault prowlarrUrl;
    };

  # Generate default applications list from enabled services
  defaultApplications = filter (app: app != {}) (map mkDefaultApplication arrServices);

  extraConfigOptions = {
    indexers = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Name of the Prowlarr Indexer Schema";
          };
          apiKeyPath = mkOption {
            type = types.str;
            description = "Path to file containing the API key for the indexer";
          };
          appProfileId = mkOption {
            type = types.int;
            default = 1;
            description = "Application profile ID for the indexer (default: 1)";
          };
        };
      });
      default = [];
      description = ''
        List of indexers to configure in Prowlarr.
        Any additional attributes beyond name, apiKeyPath, and appProfileId
        will be applied as field values to the indexer schema.
      '';
    };

    applications = mkOption {
      type = types.listOf (types.submodule {
        freeformType = types.attrsOf types.anything;
        options = {
          name = mkOption {
            type = types.str;
            description = "User-defined name for the application instance";
          };
          implementationName = mkOption {
            type = types.enum ["LazyLibrarian" "Lidarr" "Mylar" "Readarr" "Radarr" "Sonarr" "Whisper"];
            description = "Type of application to configure (matches schema implementationName)";
          };
          apiKeyPath = mkOption {
            type = types.str;
            description = "Path to file containing the API key for the application";
          };
        };
      });
      default = [];
      description = ''
        List of applications to configure in Prowlarr.
        Any additional attributes beyond name, implementationName, and apiKeyPath
        will be applied as field values to the application schema.
      '';
    };
  };
in {
  imports = [(arrCommon.mkArrServiceModule "prowlarr" extraConfigOptions)];

  config = {
    nixflix.prowlarr = {
      config = {
        apiVersion = lib.mkDefault "v1";
        hostConfig = {
          port = lib.mkDefault 9696;
          branch = lib.mkDefault "master";
        };
        applications = lib.mkDefault defaultApplications;
      };
    };

    systemd.services."prowlarr-indexers" = mkIf (config.nixflix.enable && config.nixflix.prowlarr.enable && config.nixflix.prowlarr.config.apiKeyPath != null) (
      mkProwlarrIndexersService "prowlarr" config.nixflix.prowlarr.config
    );

    systemd.services."prowlarr-applications" = mkIf (config.nixflix.enable && config.nixflix.prowlarr.enable && config.nixflix.prowlarr.config.apiKeyPath != null) (
      mkProwlarrApplicationsService "prowlarr" config.nixflix.prowlarr.config
    );
  };
}

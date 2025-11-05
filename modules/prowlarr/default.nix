{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  indexers = import ./indexers.nix {
    inherit lib pkgs;
    serviceName = "prowlarr";
  };
  applications = import ./applications.nix {
    inherit lib pkgs;
    serviceName = "prowlarr";
  };

  arrServices = ["lidarr" "radarr" "sonarr"];

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

  defaultApplications = filter (app: app != {}) (map mkDefaultApplication arrServices);

  extraConfigOptions = {
    indexers = indexers.type;

    applications = applications.type;
  };
in {
  imports = [(import ../arr-common/mkArrServiceModule.nix {inherit config lib pkgs;} "prowlarr" extraConfigOptions)];

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
      indexers.mkService config.nixflix.prowlarr.config
    );

    systemd.services."prowlarr-applications" = mkIf (config.nixflix.enable && config.nixflix.prowlarr.enable && config.nixflix.prowlarr.config.apiKeyPath != null) (
      applications.mkService config.nixflix.prowlarr.config
    );
  };
}

{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  inherit (config) nixflix;

  arrServices =
    optional nixflix.lidarr.enable "lidarr"
    ++ optional nixflix.radarr.enable "radarr"
    ++ optional nixflix.sonarr.enable "sonarr"
    ++ optional nixflix.sonarr-anime.enable "sonarr-anime";

  mkDefaultApplication =
    serviceName:
    let
      serviceConfig = nixflix.${serviceName}.config;
      # Convert service-name to "Service Name" format (e.g., "sonarr-anime" -> "Sonarr Anime")
      displayName = concatMapStringsSep " " (
        word: toUpper (builtins.substring 0 1 word) + builtins.substring 1 (-1) word
      ) (splitString "-" serviceName);

      # Map service names to their implementation names (for services with variants like sonarr-anime)
      serviceBase = builtins.elemAt (splitString "-" serviceName) 0;
      implementationName = toUpper (substring 0 1 serviceBase) + substring 1 (-1) serviceBase;

      baseUrl = "http://${serviceConfig.hostConfig.bindAddress}:${toString serviceConfig.hostConfig.port}${serviceConfig.hostConfig.urlBase}";
      prowlarrUrl = "http://${nixflix.prowlarr.config.hostConfig.bindAddress}:${toString nixflix.prowlarr.config.hostConfig.port}${nixflix.prowlarr.config.hostConfig.urlBase}";
    in
    mkIf (nixflix.${serviceName}.enable or false) {
      name = displayName;
      inherit implementationName;
      apiKey = mkDefault serviceConfig.apiKey;
      baseUrl = mkDefault baseUrl;
      prowlarrUrl = mkDefault prowlarrUrl;
    };

  defaultApplications = filter (app: app != { }) (map mkDefaultApplication arrServices);
in
{
  imports = [
    (import ../arr-common/mkArrServiceModule.nix { inherit config lib pkgs; } "prowlarr")
    ./applications.nix
    ./indexers.nix
    ./indexerProxies.nix
    ./tags.nix
  ];

  config = mkMerge [
    (mkIf (config.nixflix.enable && nixflix.prowlarr.enable) {
      assertions = map (serviceName: {
        assertion = nixflix.prowlarr.vpn.enable -> nixflix.${serviceName}.vpn.enable;
        message = "Prowlarr is VPN-confined but ${serviceName} is not. Services inside the VPN namespace cannot reach services outside it. Set `nixflix.${serviceName}.vpn.enable = true` or disable VPN for Prowlarr.";
      }) arrServices;
    })
    {
      nixflix.prowlarr.config = {
        apiVersion = lib.mkDefault "v1";
        hostConfig = {
          port = lib.mkDefault 9696;
          branch = lib.mkDefault "master";
        };
        applications = lib.mkDefault defaultApplications;
      };
    }
  ];
}

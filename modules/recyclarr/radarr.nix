{ config, lib, ... }:
let
  cfg = config.nixflix.recyclarr;
in
{
  assertions = [
    {
      assertion = config.nixflix.radarr.enable -> config.nixflix.radarr.config.apiKey != null;
      message = "Recyclarr Radarr sync requires nixflix.radarr.config.apiKey to be set";
    }
  ];

  nixflix.recyclarr.config.radarr.radarr = lib.mkIf config.nixflix.radarr.enable {
    base_url = lib.mkDefault "http://127.0.0.1:${toString config.nixflix.radarr.config.hostConfig.port}${toString config.nixflix.radarr.config.hostConfig.urlBase}";
    api_key = lib.mkDefault config.nixflix.radarr.config.apiKey;
    delete_old_custom_formats = lib.mkDefault true;

    quality_definition = {
      type = lib.mkDefault "movie";
    };

    media_naming = {
      folder = lib.mkDefault "default";
      movie = {
        rename = lib.mkDefault true;
        standard = lib.mkDefault "standard";
      };
    };

    include = lib.mkDefault (
      [
        { template = "radarr-quality-definition-sqp-streaming"; }
      ]
      ++ (
        if cfg.radarrQuality == "4K" then
          [
            { template = "radarr-quality-profile-sqp-1-2160p-default"; }
            { template = "radarr-custom-formats-sqp-1-2160p"; }
          ]
        else
          [
            { template = "radarr-quality-profile-sqp-1-1080p"; }
            { template = "radarr-custom-formats-sqp-1-1080p"; }
          ]
      )
    );
  };
}

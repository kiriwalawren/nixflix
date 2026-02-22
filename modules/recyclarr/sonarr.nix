{ config, lib, ... }:
{
  assertions = [
    {
      assertion = config.nixflix.sonarr.enable -> config.nixflix.sonarr.config.apiKey != null;
      message = "Recyclarr Sonarr sync requires nixflix.sonarr.config.apiKey to be set";
    }
  ];

  nixflix.recyclarr.config.sonarr.sonarr = lib.mkIf config.nixflix.sonarr.enable {
    base_url = lib.mkDefault "http://127.0.0.1:${toString config.nixflix.sonarr.config.hostConfig.port}${toString config.nixflix.sonarr.config.hostConfig.urlBase}";
    api_key = lib.mkDefault config.nixflix.sonarr.config.apiKey;
    delete_old_custom_formats = lib.mkDefault true;
    replace_existing_custom_formats = lib.mkDefault true;

    quality_definition = {
      type = lib.mkDefault "series";
    };

    media_naming = {
      series = lib.mkDefault "default";
      season = lib.mkDefault "default";
      episodes = {
        rename = lib.mkDefault true;
        standard = lib.mkDefault "default";
        daily = lib.mkDefault "default";
        anime = lib.mkDefault "default";
      };
    };

    include = lib.mkDefault [
      { template = "sonarr-quality-definition-series"; }
      { template = "sonarr-v4-quality-profile-web-1080p-alternative"; }
      { template = "sonarr-v4-custom-formats-web-1080p"; }
    ];
  };
}

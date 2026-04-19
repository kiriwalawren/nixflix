{ config, lib, ... }:
{
  assertions = [
    {
      assertion = config.nixflix.sonarr-anime.enable -> config.nixflix.sonarr-anime.config.apiKey != null;
      message = "Recyclarr Sonarr Anime sync requires nixflix.sonarr-anime.config.apiKey to be set";
    }
  ];

  nixflix.recyclarr.config.sonarr.sonarr_anime = lib.mkIf config.nixflix.sonarr-anime.enable {
    base_url = lib.mkDefault "http://${config.nixflix.sonarr-anime.config.hostConfig.bindAddress}:${toString config.nixflix.sonarr-anime.config.hostConfig.port}${toString config.nixflix.sonarr-anime.config.hostConfig.urlBase}";
    api_key = lib.mkDefault config.nixflix.sonarr-anime.config.apiKey;
    delete_old_custom_formats = lib.mkDefault true;

    quality_definition = {
      type = lib.mkDefault "anime";
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

    quality_profiles = lib.mkDefault [
      {
        trash_id = "20e0fc959f1f1704bed501f23bdae76f"; # [Anime] Remux-1080p
        reset_unmatched_scores.enabled = true;
      }
    ];
  };
}

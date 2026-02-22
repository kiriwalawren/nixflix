{ config, lib, ... }:
{
  assertions = [
    {
      assertion = config.nixflix.sonarr-anime.enable -> config.nixflix.sonarr-anime.config.apiKey != null;
      message = "Recyclarr Sonarr Anime sync requires nixflix.sonarr-anime.config.apiKey to be set";
    }
  ];

  nixflix.recyclarr.config.sonarr.sonarr_anime = lib.mkIf config.nixflix.sonarr-anime.enable {
    base_url = lib.mkDefault "http://127.0.0.1:${toString config.nixflix.sonarr-anime.config.hostConfig.port}${toString config.nixflix.sonarr-anime.config.hostConfig.urlBase}";
    api_key = lib.mkDefault config.nixflix.sonarr-anime.config.apiKey;
    delete_old_custom_formats = lib.mkDefault true;
    replace_existing_custom_formats = lib.mkDefault true;

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

    include = lib.mkDefault [
      { template = "sonarr-quality-definition-anime"; }
      { template = "sonarr-v4-quality-profile-anime"; }
      { template = "sonarr-v4-custom-formats-anime"; }
    ];

    custom_formats = lib.mkDefault [
      {
        trash_ids = [ "026d5aadd1a6b4e550b134cb6c72b3ca" ]; # Uncensored
        assign_scores_to = [
          {
            name = "Remux-1080p - Anime";
            score = 0;
          }
        ];
      }

      {
        trash_ids = [ "026d5aadd1a6b4e550b134cb6c72b3ca" ]; # 10bit
        assign_scores_to = [
          {
            name = "Remux-1080p - Anime";
            score = 0;
          }
        ];
      }

      {
        trash_ids = [ "026d5aadd1a6b4e550b134cb6c72b3ca" ]; # Anime Dual Audio
        assign_scores_to = [
          {
            name = "Remux-1080p - Anime";
            score = 0;
          }
        ];
      }
    ];
  };
}

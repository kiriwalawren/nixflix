{ config, lib, ... }:
let
  cfg = config.nixflix.recyclarr;
in
{
  assertions = [
    {
      assertion = config.nixflix.sonarr.enable -> config.nixflix.sonarr.config.apiKey != null;
      message = "Recyclarr Sonarr sync requires nixflix.sonarr.config.apiKey to be set";
    }
  ];

  nixflix.recyclarr.config.sonarr.sonarr = lib.mkIf config.nixflix.sonarr.enable {
    base_url = lib.mkDefault "http://${config.nixflix.sonarr.config.hostConfig.bindAddress}:${toString config.nixflix.sonarr.config.hostConfig.port}${toString config.nixflix.sonarr.config.hostConfig.urlBase}";
    api_key = lib.mkDefault config.nixflix.sonarr.config.apiKey;
    delete_old_custom_formats = lib.mkDefault true;

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

    quality_profiles = lib.mkDefault [
      {
        trash_id =
          if cfg.sonarrQuality == "4K" then
            "dfa5eaae7894077ad6449169b6eb03e0" # WEB-2160p (Alternative)
          else
            "9d142234e45d6143785ac55f5a9e8dc9"; # WEB-1080p (Alternative)
        reset_unmatched_scores.enabled = true;
      }
    ];
  };
}

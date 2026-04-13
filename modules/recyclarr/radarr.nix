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
      type = lib.mkDefault "sqp-streaming";
    };

    media_naming = {
      folder = lib.mkDefault "default";
      movie = {
        rename = lib.mkDefault true;
        standard = lib.mkDefault "standard";
      };
    };

    quality_profiles = lib.mkDefault [
      {
        trash_id =
          if cfg.radarrQuality == "4K" then
            "5128baeb2b081b72126bc8482b2a86a0" # [SQP] SQP-1 (2160p)
          else
            "0896c29d74de619df168d23b98104b22"; # [SQP] SQP-1 (1080p)
        reset_unmatched_scores.enabled = true;
      }
    ];
  };
}

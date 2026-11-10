{ lib, notifLib, ... }:
with lib;
with notifLib;
mkConnectorOption {
  implementationName = "Notifiarr";
  description = "Notifiarr notification definition for Starr services.";
  triggers = mkTriggers {
    sonarr = [ ];
    radarr = [ ];
    lidarr = [ ];
  };
  # Sonarr names this field apiKey, Radarr and Lidarr name it aPIKey.
  fields = cfg: {
    apiKey = secretField "Your API key from your Notifiarr profile.";
    aPIKey = mkOption {
      type = types.anything;
      internal = true;
      default = cfg.apiKey;
      description = "Alias of apiKey for the Radarr and Lidarr field name.";
    };
  };
}

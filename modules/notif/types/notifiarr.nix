{ lib, notifLib, ... }:
with lib;
with notifLib;
let
  aPIKey = cfg: {
    aPIKey = mkOption {
      type = types.anything;
      internal = true;
      default = cfg.apiKey;
      description = "Alias of apiKey under the field name this service uses.";
    };
  };
in
mkConnectorOption {
  implementationName = "Notifiarr";
  description = "Notifiarr notification definition for Starr services.";
  perService = {
    sonarr = { };
    radarr.fields = aPIKey;
    lidarr.fields = aPIKey;
  };
  fields = {
    apiKey = secretField "Your API key from your Notifiarr profile.";
  };
}

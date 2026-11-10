{ lib, notifLib, ... }:
with lib;
with notifLib;
mkConnectorOption {
  implementationName = "Simplepush";
  description = "Simplepush notification definition for Starr services.";
  triggers = mkTriggers {
    sonarr = [ "onRename" ];
    radarr = [ "onRename" ];
    lidarr = [
      "onRename"
      "onTrackRetag"
    ];
  };
  fields = {
    key = secretField "Simplepush key.";
    event = field types.str "Event used to customize push notification behavior.";
  };
}

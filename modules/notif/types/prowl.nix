{ lib, notifLib, ... }:
with lib;
with notifLib;
mkConnectorOption {
  implementationName = "Prowl";
  description = "Prowl notification definition for Starr services.";
  triggers = mkTriggers {
    sonarr = [ "onRename" ];
    radarr = [ "onRename" ];
    lidarr = [
      "onRename"
      "onDownloadFailure"
      "onImportFailure"
      "onTrackRetag"
    ];
  };
  fields = {
    apiKey = secretField "Prowl API key.";
    priority = field (types.enum [
      (-2)
      (-1)
      0
      1
      2
    ]) "Priority: -2 = Very Low, -1 = Low, 0 = Normal, 1 = High, 2 = Emergency.";
  };
}

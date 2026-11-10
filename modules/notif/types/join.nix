{ lib, notifLib, ... }:
with lib;
with notifLib;
mkConnectorOption {
  implementationName = "Join";
  description = "Join notification definition for Starr services.";
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
    apiKey = secretField "The API key from your Join account settings.";
    deviceIds = field types.str "Deprecated, use deviceNames instead. Comma-separated device IDs.";
    deviceNames = field types.str "Comma-separated full or partial device names. If unset, all devices receive notifications.";
    priority = field (types.enum [
      (-2)
      (-1)
      0
      1
      2
    ]) "Priority: -2 = Silent, -1 = Quiet, 0 = Normal, 1 = High, 2 = Emergency.";
  };
}

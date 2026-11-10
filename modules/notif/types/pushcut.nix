{ lib, notifLib, ... }:
with lib;
with notifLib;
mkConnectorOption {
  implementationName = "Pushcut";
  description = "Pushcut notification definition for Starr services.";
  triggers = mkTriggers {
    sonarr = [ "onRename" ];
    radarr = [ "onRename" ];
    lidarr = [
      "onRename"
      "onTrackRetag"
    ];
  };
  fields = {
    notificationName = field types.str "Notification name from the Notifications tab of the Pushcut app.";
    apiKey = secretField "Pushcut API key.";
    timeSensitive = field types.bool "Mark the notification as time sensitive.";
    includePoster = field types.bool "Include the poster with the notification. Radarr only.";
    metadataLinks = field (types.listOf types.int) "Metadata links to add to notifications; see the notification schema. Radarr only.";
  };
}

{ lib, notifLib, ... }:
with lib;
with notifLib;
mkConnectorOption {
  implementationName = "Pushcut";
  description = "Pushcut notification definition for Starr services.";
  perService = {
    sonarr.unsupportedTriggers = [ "onRename" ];
    radarr = {
      unsupportedTriggers = [ "onRename" ];
      fields = {
        includePoster = field types.bool "Include the poster with the notification.";
        metadataLinks = field (types.listOf (
          types.enum [
            0
            1
            2
          ]
        )) "Metadata links to add: 0 TMDb, 1 IMDb, 2 Trakt.";
      };
    };
    lidarr.unsupportedTriggers = [
      "onRename"
      "onTrackRetag"
    ];
  };
  fields = {
    notificationName = field types.str "Notification name from the Notifications tab of the Pushcut app.";
    apiKey = secretField "Pushcut API key.";
    timeSensitive = field types.bool "Mark the notification as time sensitive.";
  };
}

{ lib, notifLib, ... }:
with lib;
with notifLib;
mkConnectorOption {
  implementationName = "Pushbullet";
  description = "Pushbullet notification definition for Starr services.";
  triggers = mkTriggers {
    sonarr = [ "onRename" ];
    radarr = [ "onRename" ];
    lidarr = [
      "onRename"
      "onTrackRetag"
    ];
  };
  fields = {
    apiKey = secretField "Pushbullet access token.";
    deviceIds = field (types.listOf types.str) "Device IDs to send to. If unset, all devices receive notifications.";
    channelTags = field (types.listOf types.str) "Channel tags to send notifications to.";
    senderId = field types.str "Device ID to send notifications from. If unset, notifications are sent from yourself.";
  };
}

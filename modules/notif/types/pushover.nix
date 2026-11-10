{ lib, notifLib, ... }:
with lib;
with notifLib;
mkConnectorOption {
  implementationName = "Pushover";
  description = "Pushover notification definition for Starr services.";
  perService = {
    sonarr.unsupportedTriggers = [ "onRename" ];
    radarr = {
      unsupportedTriggers = [ "onRename" ];
      fields.ttl = field types.int "Seconds before the message expires, 0 for unlimited.";
    };
    lidarr.unsupportedTriggers = [
      "onRename"
      "onTrackRetag"
    ];
  };
  fields = {
    apiKey = secretField "Pushover API key.";
    userKey = secretField "Pushover user key.";
    devices = field (types.listOf types.str) "Device names to send to. If unset, all devices receive notifications.";
    priority = field (types.enum [
      (-2)
      (-1)
      0
      1
      2
    ]) "Priority: -2 = Silent, -1 = Quiet, 0 = Normal, 1 = High, 2 = Emergency.";
    retry = field types.int "Interval to retry emergency alerts, minimum 30 seconds.";
    expire = field types.int "Maximum time to retry emergency alerts, maximum 86400 seconds.";
    sound = field types.str "Notification sound. If unset, the default is used.";
  };
}

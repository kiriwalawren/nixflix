{ lib, notifLib, ... }:
with lib;
with notifLib;
mkConnectorOption {
  implementationName = "Pushsafer";
  description = "Pushsafer notification definition for Radarr.";
  services = [ "radarr" ];
  triggers = mkTriggers { radarr = [ "onRename" ]; };
  fields = {
    apiKey = secretField "Pushsafer API key.";
    deviceIds = field (types.listOf types.str) "Device group ID or device IDs. If unset, all devices receive notifications.";
    priority = field (types.enum [
      (-2)
      (-1)
      0
      1
      2
    ]) "Priority: -2 = Silent, -1 = Quiet, 0 = Normal, 1 = High, 2 = Emergency.";
    retry = field types.int "Interval to retry emergency alerts, minimum 60 seconds.";
    expire = field types.int "Maximum time to retry emergency alerts, maximum 10800 seconds.";
    sound = field types.str "Notification sound 0-62. If unset, the default is used.";
    vibration = field types.str "Vibration pattern 1-3. If unset, the device default is used.";
    icon = field types.str "Icon number 1-181. If unset, the default Pushsafer icon is used.";
    iconColor = field types.str "Icon color in hex. If unset, the default color is used.";
  };
}

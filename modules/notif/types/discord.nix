{ lib, notifLib, ... }:
with lib;
with notifLib;
mkConnectorOption {
  implementationName = "Discord";
  description = "Discord notification definition for Starr services.";
  triggers = mkTriggers {
    sonarr = [ ];
    radarr = [ ];
    lidarr = [ ];
  };
  fields = {
    webHookUrl = secretField "Discord channel webhook URL.";
    username = secretField "The username to post as. Defaults to the Discord webhook default.";
    avatar = field types.str "Avatar used for messages from this integration.";
    author = field types.str "Override the embed author (host on Lidarr) shown for this notification.";
    grabFields = field (types.listOf types.int) "Values of the fields passed in an on-grab notification. The values differ per Starr service; see the notification schema.";
    importFields = field (types.listOf types.int) "Values of the fields passed in an on-import notification. The values differ per Starr service; see the notification schema.";
    manualInteractionFields = field (types.listOf types.int) "Values of the fields passed in a manual-interaction notification. Sonarr and Radarr only.";
  };
}

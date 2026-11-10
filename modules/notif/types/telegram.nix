{ lib, notifLib, ... }:
with lib;
with notifLib;
mkConnectorOption {
  implementationName = "Telegram";
  description = "Telegram notification definition for Starr services.";
  triggers = mkTriggers {
    sonarr = [ "onRename" ];
    radarr = [ "onRename" ];
    lidarr = [
      "onRename"
      "onTrackRetag"
    ];
  };
  fields = {
    botToken = secretField "Telegram bot token.";
    chatId = field types.str "Chat ID. Start a conversation with the bot or add it to your group first.";
    topicId = field types.str "Topic ID to send notifications to (supergroups only). If unset, the general topic is used.";
    sendSilently = field types.bool "Send the message silently, with no notification sound.";
    includeAppNameInTitle = field types.bool "Prefix the message title with the Starr application name.";
    includeInstanceNameInTitle = field types.bool "Include the instance name in the notification. Sonarr and Radarr only.";
    metadataLinks = field (types.listOf types.int) "Metadata links to add to notifications. The values differ per Starr service; see the notification schema. Sonarr and Radarr only.";
  };
}

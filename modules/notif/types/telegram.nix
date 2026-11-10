{ lib, notifLib, ... }:
with lib;
with notifLib;
let
  includeInstanceNameInTitle = field types.bool "Include the instance name in the notification.";
in
mkConnectorOption {
  implementationName = "Telegram";
  description = "Telegram notification definition for Starr services.";
  perService = {
    seerr = {
      agent = "telegram";
      mappedFields = [
        "botToken"
        "chatId"
        "topicId"
        "sendSilently"
      ];
      fields.botUsername = field types.str "Bot username, which Seerr shows users so they can start a chat with the bot.";
      toSeerr =
        r:
        seerrOptions r {
          botAPI = "botToken";
          chatId = "chatId";
          messageThreadId = "topicId";
          sendSilently = "sendSilently";
          botUsername = "botUsername";
        };
      required = r: [ "botToken" ] ++ optional (seerrTypes r != 0) "chatId";
    };
    sonarr = {
      unsupportedTriggers = [ "onRename" ];
      fields = {
        inherit includeInstanceNameInTitle;
        metadataLinks = field (types.listOf (
          types.enum [
            0
            1
            2
            3
          ]
        )) "Metadata links to add: 0 IMDb, 1 TVDb, 2 TVMaze, 3 Trakt.";
      };
    };
    radarr = {
      unsupportedTriggers = [ "onRename" ];
      fields = {
        inherit includeInstanceNameInTitle;
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
    botToken = secretField "Telegram bot token.";
    chatId = field types.str "Chat ID. Start a conversation with the bot or add it to your group first.";
    topicId = field types.str "Topic ID to send notifications to (supergroups only). If unset, the general topic is used.";
    sendSilently = field types.bool "Send the message silently, with no notification sound.";
    includeAppNameInTitle = field types.bool "Prefix the message title with the Starr application name.";
  };
}

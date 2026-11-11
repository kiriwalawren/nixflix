{ lib, notifLib, ... }:
with lib;
with notifLib;
mkConnectorOption {
  implementationName = "Slack";
  description = "Slack notification definition for Starr services.";
  perService = {
    seerr = {
      agent = "slack";
      mappedFields = [ "webHookUrl" ];
      fields.locale = field types.str "Language of Seerr's notification text, for example `en`.";
      toSeerr =
        r:
        seerrOptions r {
          webhookUrl = "webHookUrl";
          locale = "locale";
        };
      required = _: [ "webHookUrl" ];
    };
    sonarr.unsupportedTriggers = [ ];
    radarr.unsupportedTriggers = [ "onMovieAdded" ];
    lidarr.unsupportedTriggers = [ ];
  };
  fields = {
    webHookUrl = secretField "Slack channel webhook URL.";
    username = secretField "Username to post to Slack as.";
    icon = field types.str "Icon used for messages posted to Slack (emoji or URL).";
    channel = field types.str "Overrides the default channel for the incoming webhook.";
  };
}

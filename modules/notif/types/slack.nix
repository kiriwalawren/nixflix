{ lib, notifLib, ... }:
with lib;
with notifLib;
mkConnectorOption {
  implementationName = "Slack";
  description = "Slack notification definition for Starr services.";
  perService = {
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

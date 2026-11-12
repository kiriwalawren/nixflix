{ lib, notifLib, ... }:
with lib;
with notifLib;
mkConnectorOption {
  implementationName = "Twitter";
  description = "Twitter / X notification definition for Starr services.";
  perService = {
    sonarr.unsupportedTriggers = [ "onRename" ];
    radarr.unsupportedTriggers = [ "onRename" ];
    lidarr.unsupportedTriggers = [
      "onRename"
      "onTrackRetag"
    ];
  };
  fields = {
    consumerKey = secretField "Consumer key from a Twitter application.";
    consumerSecret = secretField "Consumer secret from a Twitter application.";
    accessToken = secretField "Access token.";
    accessTokenSecret = secretField "Access token secret.";
    mention = field types.str "Mention this user in sent tweets.";
    directMessage = field types.bool "Send a direct message instead of a public message.";
  };
}

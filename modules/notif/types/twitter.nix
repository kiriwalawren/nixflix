{ lib, notifLib, ... }:
with lib;
with notifLib;
mkConnectorOption {
  implementationName = "Twitter";
  description = "Twitter / X notification definition for Starr services.";
  triggers = mkTriggers {
    sonarr = [ "onRename" ];
    radarr = [ "onRename" ];
    lidarr = [
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

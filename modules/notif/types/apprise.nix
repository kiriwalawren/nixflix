{ lib, notifLib, ... }:
with lib;
with notifLib;
mkConnectorOption {
  implementationName = "Apprise";
  description = "Apprise notification definition for Starr services.";
  perService = {
    sonarr.unsupportedTriggers = [ "onRename" ];
    radarr = {
      unsupportedTriggers = [ "onRename" ];
      fields.includePoster = field types.bool "Include the poster in the message.";
    };
    lidarr.unsupportedTriggers = [
      "onRename"
      "onTrackRetag"
    ];
  };
  fields = {
    serverUrl = field types.str "Apprise server URL, including http(s):// and port if needed.";
    configurationKey = field types.str "Configuration key for the persistent storage solution. Leave unset if stateless URLs are used.";
    statelessUrls = secretField "One or more comma-separated URLs identifying where the notification should be sent. Leave unset if persistent storage is used.";
    notificationType = field (types.enum [
      0
      1
      2
      3
    ]) "Apprise notification type: 0 = Info, 1 = Success, 2 = Warning, 3 = Failure.";
    tags = field (types.listOf types.str) "Only notify Apprise targets tagged accordingly.";
    authUsername = secretField "HTTP basic auth username.";
    authPassword = secretField "HTTP basic auth password.";
  };
}

{ lib, notifLib, ... }:
with lib;
with notifLib;
mkConnectorOption {
  implementationName = "Signal";
  description = "Signal notification definition for Starr services.";
  perService = {
    sonarr.unsupportedTriggers = [ "onRename" ];
    radarr.unsupportedTriggers = [ "onRename" ];
    lidarr.unsupportedTriggers = [
      "onRename"
      "onTrackRetag"
    ];
  };
  fields = {
    host = field types.str "Host of the signal-api server.";
    port = field types.port "Port of the signal-api server.";
    useSsl = field types.bool "Connect to signal-api over HTTPS instead of HTTP.";
    senderNumber = secretField "Phone number of the sender registered in signal-api.";
    receiverId = field types.str "Group ID or phone number of the receiver.";
    authUsername = secretField "Username used to authenticate requests to signal-api.";
    authPassword = secretField "Password used to authenticate requests to signal-api.";
  };
}

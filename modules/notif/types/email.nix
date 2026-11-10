{ lib, notifLib, ... }:
with lib;
with notifLib;
let
  useEncryption = field (types.enum [
    0
    1
    2
  ]) "Encryption mode: 0 = Preferred, 1 = Always, 2 = Never.";
in
mkConnectorOption {
  implementationName = "Email";
  description = "Email notification definition for Starr services.";
  perService = {
    sonarr = {
      unsupportedTriggers = [ "onRename" ];
      fields = { inherit useEncryption; };
    };
    radarr = {
      unsupportedTriggers = [ "onRename" ];
      fields = { inherit useEncryption; };
    };
    lidarr = {
      unsupportedTriggers = [
        "onRename"
        "onTrackRetag"
      ];
      fields.requireEncryption = field types.bool "Require SSL (port 465 only) or StartTLS (any other port).";
    };
  };
  fields = {
    server = field types.str "Hostname or IP of the email server.";
    port = field types.port "Port of the email server.";
    username = secretField "Username for the email server.";
    password = secretField "Password for the email server.";
    from = field types.str "From address.";
    to = field (types.listOf types.str) "Recipient addresses.";
    cc = field (types.listOf types.str) "CC addresses.";
    bcc = field (types.listOf types.str) "BCC addresses.";
  };
}

{
  lib,
  secrets,
  notifLib,
  ...
}:
with lib;
with notifLib;
mkConnectorOption {
  implementationName = "Webhook";
  description = "Webhook notification definition for Starr services.";
  perService = {
    sonarr.unsupportedTriggers = [ ];
    radarr.unsupportedTriggers = [ ];
    lidarr.unsupportedTriggers = [ ];
  };
  fields = {
    url = secretField "Webhook URL.";
    method = field (types.enum [
      1
      2
    ]) "HTTP method: 1 = POST, 2 = PUT.";
    username = secretField "Username for the webhook.";
    password = secretField "Password for the webhook.";
    headers = field (types.listOf (
      types.submodule {
        options = {
          key = mkOption {
            type = types.str;
            description = "Header name.";
          };
          value = secrets.mkSecretOption { description = "Header value."; };
        };
      }
    )) "HTTP headers to send with each request.";
  };
}

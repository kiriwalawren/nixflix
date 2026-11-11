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
    seerr = {
      agent = "webhook";
      mappedFields = [
        "url"
        "headers"
        "username"
        "password"
      ];
      fields = {
        authHeader = secretField "Authorization header value Seerr sends with each request. Conflicts with `username`/`password`, which Seerr sends as a Basic authorization header.";
        jsonPayload = field types.str "JSON payload template Seerr sends. Null keeps Seerr's current template, which defaults to Seerr's built-in one.";
        supportVariables = field types.bool "Whether Seerr substitutes template variables in the webhook URL.";
      };
      toSeerr =
        r:
        seerrOptions r {
          webhookUrl = "url";
          customHeaders = "headers";
          authHeader = "authHeader";
          jsonPayload = "jsonPayload";
          supportVariables = "supportVariables";
          __basicUser = "username";
          __basicPass = "password";
        };
      jqPost = ''
        (if .options.__basicUser != null then
          .options.authHeader = ("Basic " + ((.options.__basicUser + ":" + (.options.__basicPass // "")) | @base64))
        else . end)
        | del(.options.__basicUser, .options.__basicPass)
      '';
      required = _: [ "url" ];
      checks = r: [
        {
          assertion =
            (r.authHeader or null) == null || ((r.username or null) == null && (r.password or null) == null);
          message = "`nixflix.notif.webhook` sets both `authHeader` and `username`/`password` for Seerr, but Seerr sends a single Authorization header. Set only one.";
        }
      ];
    };
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

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
    seerr = {
      agent = "email";
      hasTypes = false;
      mappedFields = [
        "server"
        "port"
        "username"
        "password"
        "from"
      ];
      fields = {
        inherit useEncryption;
        senderName = field types.str "Sender name Seerr uses in emails.";
        allowSelfSigned = field types.bool "Whether Seerr allows self-signed certificates on the email server.";
        userEmailRequired = field types.bool "Whether Seerr requires users to provide an email address.";
        usePublicLogo = field types.bool "Whether Seerr's emails link to the public Seerr logo instead of embedding it.";
        pgpPrivateKey = secretField "PGP private key Seerr signs emails with. Requires `pgpPassword`.";
        pgpPassword = secretField "Password for `pgpPrivateKey`. Requires `pgpPrivateKey`.";
      };
      toSeerr =
        r:
        seerrOptions r {
          smtpHost = "server";
          smtpPort = "port";
          authUser = "username";
          authPass = "password";
          emailFrom = "from";
          senderName = "senderName";
          allowSelfSigned = "allowSelfSigned";
          userEmailRequired = "userEmailRequired";
          usePublicLogo = "usePublicLogo";
          pgpPrivateKey = "pgpPrivateKey";
          pgpPassword = "pgpPassword";
          __useEncryption = "useEncryption";
        };
      jqPost = ''
        (if .options.__useEncryption != null then
          .options.__useEncryption as $e
          | .options.secure = ($e == 1 and .options.smtpPort == 465)
          | .options.requireTls = ($e == 1 and .options.smtpPort != 465)
          | .options.ignoreTls = ($e == 2)
        else . end)
        | del(.options.__useEncryption)
      '';
      required =
        r:
        [
          "server"
          "from"
        ]
        ++ optional ((r.pgpPassword or null) != null) "pgpPrivateKey"
        ++ optional ((r.pgpPrivateKey or null) != null) "pgpPassword";
    };
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

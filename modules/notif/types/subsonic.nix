{
  config,
  lib,
  secrets,
  notifLib,
}:
with lib;
let
  getFirstAdmin = import ../../../lib/getFirstAdmin.nix { inherit lib; };

  navidromeAdmin =
    (getFirstAdmin {
      inherit (config.nixflix.navidrome) users;
      isAdmin = user: user.isAdmin;
    }).user;

  triggers.lidarr = {
    valid = [
      "onGrab"
      "onReleaseImport"
      "onUpgrade"
      "onRename"
      "onArtistAdd"
      "onArtistDelete"
      "onAlbumDelete"
      "onHealthIssue"
      "onTrackRetag"
    ];
    default = [
      "onGrab"
      "onReleaseImport"
      "onUpgrade"
      "onRename"
      "onArtistAdd"
      "onArtistDelete"
      "onHealthIssue"
      "onTrackRetag"
    ];
  };
in
mkOption {
  type = notifLib.mkNotificationType {
    implementationName = "Subsonic";

    enable = {
      default = config.nixflix.navidrome.enable;
      defaultText = literalExpression "config.nixflix.navidrome.enable";
    };

    dependencies.default = [ "navidrome.service" ];

    services.default = [ "lidarr" ];

    perService = mapAttrs (_: t: { triggers = t; }) triggers;
    removedOptions = {
      triggers = "Use the boolean trigger options instead, for example `nixflix.notif.subsonic.onGrab = false;` or `nixflix.notif.subsonic.lidarr.onTrackRetag = false;`.";
    };

    extraOptions = {
      useSsl = notifLib.field types.bool "Connect to Subsonic over HTTPS instead of HTTP.";
      urlBase = notifLib.field types.str "Prefix for the Subsonic URL.";
      notify = notifLib.field types.bool "Notify with a chat message.";
      updateLibrary = notifLib.field types.bool "Update the library on download and rename.";

      host = mkOption {
        type = types.str;
        description = "Host of the Navidrome (Subsonic) server.";
        default = config.nixflix.navidrome.connectionAddress;
        defaultText = literalExpression "config.nixflix.navidrome.connectionAddress";
      };

      port = mkOption {
        type = types.port;
        description = "Port of the Navidrome (Subsonic) server.";
        default = config.nixflix.navidrome.settings.Port;
        defaultText = literalExpression "config.nixflix.navidrome.settings.Port";
      };

      username = secrets.mkSecretOption {
        description = "Username for the Navidrome (Subsonic) server.";
        default = navidromeAdmin.userName or null;
        defaultText = literalExpression "(getFirstAdmin { inherit (config.nixflix.navidrome) users; isAdmin = user: user.isAdmin; }).user.userName";
        nullable = true;
      };

      password = secrets.mkSecretOption {
        description = "Password for the Navidrome (Subsonic) server.";
        default = navidromeAdmin.password or null;
        defaultText = literalExpression "(getFirstAdmin { inherit (config.nixflix.navidrome) users; isAdmin = user: user.isAdmin; }).user.password";
        nullable = true;
      };
    };
  };
  default = { };
  description = "Subsonic notification definition for Starr services.";
}

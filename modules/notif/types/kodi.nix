{ lib, notifLib, ... }:
with lib;
with notifLib;
mkConnectorOption {
  implementationName = "Kodi";
  description = "Kodi notification definition for Starr services.";
  perService = {
    sonarr = { };
    radarr.unsupportedTriggers = [ "onMovieAdded" ];
    lidarr.unsupportedTriggers = [
      "onAlbumDelete"
      "onDownloadFailure"
      "onImportFailure"
    ];
  };
  fields = {
    host = field types.str "Host of the Kodi server.";
    port = field types.port "Port of the Kodi server.";
    useSsl = field types.bool "Connect to Kodi over HTTPS instead of HTTP.";
    urlBase = field types.str "Prefix for the Kodi URL, such as /jsonrpc.";
    username = secretField "Username for the Kodi server.";
    password = secretField "Password for the Kodi server.";
    displayTime = field types.int "How long the notification is displayed, in seconds.";
    notify = field types.bool "Show a GUI notification.";
    updateLibrary = field types.bool "Update the library on import and rename.";
    cleanLibrary = field types.bool "Clean the library after an update.";
    alwaysUpdate = field types.bool "Update the library even when a video is playing.";
  };
}

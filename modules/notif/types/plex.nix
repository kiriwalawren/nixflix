{ lib, notifLib, ... }:
with lib;
with notifLib;
mkConnectorOption {
  implementationName = "Plex Media Server";
  description = "Plex Media Server notification definition for Starr services.";
  perService = {
    sonarr.unsupportedTriggers = [
      "onGrab"
      "onHealthIssue"
      "onHealthRestored"
      "onApplicationUpdate"
      "onManualInteractionRequired"
    ];
    radarr.unsupportedTriggers = [
      "onGrab"
      "onMovieAdded"
      "onHealthIssue"
      "onHealthRestored"
      "onApplicationUpdate"
      "onManualInteractionRequired"
    ];
    lidarr.unsupportedTriggers = [
      "onGrab"
      "onHealthIssue"
      "onHealthRestored"
      "onDownloadFailure"
      "onImportFailure"
      "onApplicationUpdate"
    ];
  };
  fields = {
    host = field types.str "Host of the Plex server.";
    port = field types.port "Port of the Plex server.";
    useSsl = field types.bool "Connect to Plex over HTTPS instead of HTTP.";
    urlBase = field types.str "Prefix for the Plex URL.";
    authToken = secretField "Plex auth token. Set this directly instead of authenticating through Plex.tv.";
    updateLibrary = field types.bool "Update the library.";
    mapFrom = field types.str "Starr path to rewrite when Plex sees the library path differently (requires updateLibrary).";
    mapTo = field types.str "Plex path that mapFrom is rewritten to (requires updateLibrary).";
  };
}

{ lib, notifLib, ... }:
with lib;
with notifLib;
mkConnectorOption {
  implementationName = "Synology Indexer";
  description = "Synology Indexer notification definition for Starr services.";
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
    updateLibrary = field types.bool "Call synoindex on localhost to update a library file.";
  };
}

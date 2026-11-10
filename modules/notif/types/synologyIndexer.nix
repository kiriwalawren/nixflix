{ lib, notifLib, ... }:
with lib;
with notifLib;
mkConnectorOption {
  implementationName = "Synology Indexer";
  description = "Synology Indexer notification definition for Starr services.";
  triggers = mkTriggers {
    sonarr = [
      "onGrab"
      "onHealthIssue"
      "onHealthRestored"
      "onApplicationUpdate"
      "onManualInteractionRequired"
    ];
    radarr = [
      "onGrab"
      "onMovieAdded"
      "onHealthIssue"
      "onHealthRestored"
      "onApplicationUpdate"
      "onManualInteractionRequired"
    ];
    lidarr = [
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

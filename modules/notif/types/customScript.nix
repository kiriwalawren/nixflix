{ lib, notifLib, ... }:
with lib;
with notifLib;
mkConnectorOption {
  implementationName = "Custom Script";
  description = "Custom Script notification definition for Starr services.";
  triggers = mkTriggers {
    sonarr = [ ];
    radarr = [ ];
    lidarr = [
      "onDownloadFailure"
      "onImportFailure"
    ];
  };
  fields = {
    path = field types.str "Path to the script to execute.";
    arguments = field types.str "Arguments to pass to the script.";
  };
}

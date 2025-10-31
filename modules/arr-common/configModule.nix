extraConfigOptions: {lib}:
with lib;
  types.submodule {
    options =
      {
        apiVersion = mkOption {
          type = types.str;
          default = "v3";
          description = "Current version of the API of the service";
        };

        apiKeyPath = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Path to API key secret file";
        };

        hostConfig = mkOption {
          type = import ./hostConfigModule.nix {inherit lib;};
          default = {};
          description = "Host configuration options that will be set via the API /config/host endpoint";
        };

        rootFolders = mkOption {
          type = types.listOf types.attrs;
          default = [];
          description = ''
            List of root folders to create via the API /rootfolder endpoint.
            Each folder is an attribute set that will be converted to JSON and sent to the API.

            For Sonarr/Radarr, a simple path is sufficient: {path = "/path/to/folder";}
            For Lidarr, additional fields are required like defaultQualityProfileId, etc.
          '';
        };
      }
      // extraConfigOptions;
  }

{lib}: extraConfigOptions:
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
      }
      // extraConfigOptions;
  }

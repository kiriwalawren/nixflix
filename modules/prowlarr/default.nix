{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  mkProwlarrIndexersService = import ./indexersService.nix {inherit lib pkgs;};
  arrCommon = import ../arr-common {
    inherit config lib pkgs;
  };

  extraConfigOptions = {
    indexers = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Name of the Prowlarr Indexer Schema";
          };
          apiKeyPath = mkOption {
            type = types.str;
            description = "Path to file containing the API key for the indexer";
          };
          appProfileId = mkOption {
            type = types.int;
            default = 1;
            description = "Application profile ID for the indexer (default: 1)";
          };
        };
      });
      default = [];
      description = ''
        List of indexers to configure in Prowlarr.
        Any additional attributes beyond name, apiKeyPath, and appProfileId
        will be applied as field values to the indexer schema.
      '';
    };
  };
in {
  imports = [(arrCommon.mkArrServiceModule "prowlarr" extraConfigOptions)];

  config = {
    nixflix.prowlarr = {
      config = {
        apiVersion = lib.mkDefault "v1";
        hostConfig = {
          port = lib.mkDefault 9696;
          branch = lib.mkDefault "master";
        };
      };
    };

    systemd.services."prowlarr-indexers" = mkIf (config.nixflix.enable && config.nixflix.prowlarr.enable && config.nixflix.prowlarr.config.apiKeyPath != null) (
      mkProwlarrIndexersService "prowlarr" config.nixflix.prowlarr.config
    );
  };
}

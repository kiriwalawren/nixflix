{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (config) nixflix;
  cfg = config.nixflix.lidarr;
in {
  imports = [(import ../arr-common/mkArrServiceModule.nix {inherit config lib pkgs;} "lidarr" {})];

  config.nixflix.lidarr = {
    group = lib.mkDefault "media";
    mediaDirs = lib.mkDefault ["${nixflix.mediaDir}/music"];
    config = {
      apiVersion = lib.mkDefault "v1";
      hostConfig = {
        port = lib.mkDefault 8686;
        branch = lib.mkDefault "master";
      };
      rootFolders = lib.mkDefault (map (mediaDir: {
          path = mediaDir;
          defaultQualityProfileId = 2;
          defaultMetadataProfileId = 1;
          defaultMonitorOption = "all";
          defaultNewItemMonitorOption = "all";
          defaultTags = [];
          name = "default";
        })
        cfg.mediaDirs);
    };
  };
}

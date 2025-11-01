{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (config) nixflix;
  cfg = config.nixflix.lidarr;
  arrCommon = import ../arr-common {inherit config lib pkgs;};
in {
  imports = [(arrCommon.mkArrServiceModule "lidarr" {})];

  config.nixflix.lidarr = {
    group = lib.mkDefault "media";
    mediaDirs = lib.mkDefault [
      {dir = "${nixflix.mediaDir}/music";}
    ];
    config = {
      apiVersion = lib.mkDefault "v1";
      hostConfig = {
        port = lib.mkDefault 8686;
        branch = lib.mkDefault "master";
      };
      rootFolders = lib.mkDefault (map (mediaDir: {
          path = mediaDir.dir;
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

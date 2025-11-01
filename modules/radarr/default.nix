{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (config) nixflix;
  cfg = config.nixflix.radarr;
  arrCommon = import ../arr-common {inherit config lib pkgs;};
in {
  imports = [(arrCommon.mkArrServiceModule "radarr" {})];

  config.nixflix.radarr = {
    group = lib.mkDefault "media";
    mediaDirs = lib.mkDefault [
      {dir = "${nixflix.mediaDir}/movies";}
    ];
    config = {
      apiVersion = lib.mkDefault "v3";
      hostConfig = {
        port = lib.mkDefault 7878;
        branch = lib.mkDefault "master";
      };
      rootFolders = lib.mkDefault (map (mediaDir: {path = mediaDir.dir;}) cfg.mediaDirs);
    };
  };
}

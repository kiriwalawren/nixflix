{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (config) nixflix;
  cfg = config.nixflix.sonarr;
  arrCommon = import ../arr-common {inherit config lib pkgs;};
in {
  imports = [(arrCommon.mkArrServiceModule "sonarr" {})];

  config.nixflix.sonarr = {
    group = lib.mkDefault "media";
    mediaDirs = lib.mkDefault [
      {dir = "${nixflix.mediaDir}/tv";}
    ];
    config = {
      apiVersion = lib.mkDefault "v3";
      hostConfig = {
        port = lib.mkDefault 8989;
        branch = lib.mkDefault "main";
      };
      rootFolders = lib.mkDefault (map (mediaDir: {path = mediaDir.dir;}) cfg.mediaDirs);
    };
  };
}

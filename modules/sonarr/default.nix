{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (config) nixflix;
  cfg = config.nixflix.sonarr;
in {
  imports = [(import ../arr-common/mkArrServiceModule.nix "sonarr" {} {inherit config lib pkgs;})];

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

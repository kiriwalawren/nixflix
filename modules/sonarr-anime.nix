{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (config) nixflix;
  cfg = config.nixflix.sonarr-anime;
in {
  imports = [(import ./arr-common/mkArrServiceModule.nix {inherit config lib pkgs;} "sonarr-anime" {})];

  config.nixflix.sonarr-anime = {
    group = lib.mkDefault "media";
    mediaDirs = lib.mkDefault ["${nixflix.mediaDir}/anime"];
    config = {
      apiVersion = lib.mkDefault "v3";
      hostConfig = {
        port = lib.mkDefault 8990;
        branch = lib.mkDefault "main";
      };
      rootFolders = lib.mkDefault (map (mediaDir: {path = mediaDir;}) cfg.mediaDirs);
    };
  };
}

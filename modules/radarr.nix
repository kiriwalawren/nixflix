{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (config) nixflix;
  cfg = config.nixflix.radarr;
in {
  imports = [(import ./arr-common/mkArrServiceModule.nix {inherit config lib pkgs;} "radarr" {})];

  config.nixflix.radarr = {
    group = lib.mkDefault "media";
    mediaDirs = lib.mkDefault ["${nixflix.mediaDir}/movies"];
    config = {
      apiVersion = lib.mkDefault "v3";
      hostConfig = {
        port = lib.mkDefault 7878;
        branch = lib.mkDefault "master";
      };
      rootFolders = lib.mkDefault (map (mediaDir: {path = mediaDir;}) cfg.mediaDirs);
    };
  };
}

{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config) nixflix;
  cfg = config.nixflix.sonarr;
in
{
  imports = [
    (import ./arr-common/mkArrServiceModule.nix { inherit config lib pkgs; } "sonarr" { })
  ];

  config.nixflix.sonarr = {
    group = lib.mkDefault "media";
    mediaDirs = lib.mkDefault [ "${nixflix.mediaDir}/tv" ];
    config = {
      apiVersion = lib.mkDefault "v3";
      hostConfig = {
        port = lib.mkDefault 8989;
        branch = lib.mkDefault "main";
      };
      rootFolders = lib.mkDefault (map (mediaDir: { path = mediaDir; }) cfg.mediaDirs);
    };
  };
}

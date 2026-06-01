{
  lib,
  pkgs,
  serviceName,
}:
let
  serviceBase = builtins.elemAt (lib.splitString "-" serviceName) 0;
in
{
  inherit serviceBase;
  usesMediaDirs = !(lib.elem serviceName [ "prowlarr" ]);
  capitalizedName =
    lib.toUpper (builtins.substring 0 1 serviceName) + builtins.substring 1 (-1) serviceName;
  isSonarr = serviceBase == "sonarr";
  isRadarr = serviceBase == "radarr";
  isLidarr = serviceBase == "lidarr";
  mkSecureCurl = import ../../lib/mk-secure-curl.nix { inherit lib pkgs; };
  mkWaitForApiScript = import ./mkWaitForApiScript.nix { inherit lib pkgs; };
}

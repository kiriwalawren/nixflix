{
  lib,
  pkgs,
  serviceName,
}:
let
  serviceBase = builtins.elemAt (lib.splitString "-" serviceName) 0;
  capitalize = s: lib.toUpper (builtins.substring 0 1 s) + builtins.substring 1 (-1) s;
in
{
  inherit serviceBase capitalize;
  usesMediaDirs = !(lib.elem serviceName [ "prowlarr" ]);
  capitalizedName = capitalize serviceName;
  isSonarr = serviceBase == "sonarr";
  isRadarr = serviceBase == "radarr";
  isLidarr = serviceBase == "lidarr";
  mkSecureCurl = import ../../lib/mk-secure-curl.nix { inherit lib pkgs; };
  mkWaitForApiScript = import ./mkWaitForApiScript.nix { inherit lib pkgs; };
}

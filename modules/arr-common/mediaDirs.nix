{ serviceName }:
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix.${serviceName};
  inherit (import ./utils.nix { inherit lib pkgs serviceName; }) usesMediaDirs;
  inherit (config.nixflix) globals;
in
{
  options.nixflix.${serviceName} = optionalAttrs usesMediaDirs {
    mediaDirs = mkOption {
      type = types.listOf types.path;
      default = [ ];
      defaultText = literalExpression ''[config.nixflix.mediaDir + "/<media-type>"]'';
      description = "List of media directories to create and manage";
    };
  };

  config = mkIf (usesMediaDirs && config.nixflix.enable && cfg.enable) {
    systemd.tmpfiles.settings."10-${serviceName}" = lib.mergeAttrsList (
      map (mediaDir: {
        "${mediaDir}".d = {
          inherit (globals.libraryOwner) user group;
          mode = "0775";
        };
      }) cfg.mediaDirs
    );

    systemd.services.${serviceName}.serviceConfig = {
      SupplementaryGroups = [ globals.libraryOwner.group ];
      ReadWritePaths = cfg.mediaDirs ++ [ config.nixflix.downloadsDir ];
    };
  };
}

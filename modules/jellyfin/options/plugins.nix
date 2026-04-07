{ lib, ... }:
with lib;
{
  options.nixflix.jellyfin.plugins = mkOption {
    type = types.listOf types.package;
    default = [ ];
    description = ''
      List of Jellyfin plugin packages to install declaratively.
      Each package should produce a directory containing plugin files
      (DLLs, etc.). Nixflix names the managed plugin directory from the
      package name and version when present. Jellyfin auto-generates meta.json from assembly
      attributes on first load.
      Removing a plugin from this list removes it from disk on restart.
    '';
  };
}

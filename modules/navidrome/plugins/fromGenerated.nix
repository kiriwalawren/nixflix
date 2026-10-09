{ lib, pkgs, ... }:
let
  navidromePlugins = import ./lib/navidrome-plugins.nix { inherit lib; };
  firstClass = import ./firstClass.nix { inherit pkgs; };
  generatedFileNames = lib.filter (lib.hasSuffix "-plugin.nix") (
    lib.attrNames (lib.filterAttrs (_: type: type == "regular") (builtins.readDir ./gen))
  );
in
{
  options.nixflix.navidrome.plugins = builtins.listToAttrs (
    map (
      fileName:
      let
        pluginName = lib.removeSuffix "-plugin.nix" fileName;
        generated = import (./gen + "/${fileName}") { inherit lib; };
        firstClassEntry = firstClass.${pluginName} or { };
      in
      lib.nameValuePair pluginName (
        (navidromePlugins.mkNonConfigOptions {
          apiIdDefault = firstClassEntry.apiId or pluginName;
          packageDefault = firstClassEntry.package or null;
        })
        // {
          config = lib.mkOption {
            inherit (generated) type;
            default = { };
            inherit (generated) description;
          };
        }
      )
    ) generatedFileNames
  );
}

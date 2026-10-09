{ config, lib, ... }:
let
  cfg = config.nixflix.navidrome;
  generatedFileNames = lib.filter (lib.hasSuffix "-plugin.nix") (
    lib.attrNames (lib.filterAttrs (_: type: type == "regular") (builtins.readDir ./gen))
  );
  mkAssertionsByName = builtins.listToAttrs (
    map (
      fileName:
      let
        pluginName = lib.removeSuffix "-plugin.nix" fileName;
        generated = import (./gen + "/${fileName}") { inherit lib; };
      in
      lib.nameValuePair pluginName (generated.mkAssertions or (_: [ ]))
    ) generatedFileNames
  );
in
{
  config.assertions = lib.concatLists (
    lib.mapAttrsToList (
      pluginName: pluginCfg:
      if pluginCfg.enable && mkAssertionsByName ? ${pluginName} then
        map (a: a // { message = ''nixflix.navidrome.plugins."${pluginName}".config: ${a.message}''; }) (
          mkAssertionsByName.${pluginName} pluginCfg.config
        )
      else
        [ ]
    ) cfg.plugins
  );
}

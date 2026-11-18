{ config, lib, ... }:
let
  cfg = config.nixflix.navidrome;
  generatedFileNames = lib.filter (lib.hasSuffix "-plugin.nix") (
    lib.attrNames (lib.filterAttrs (_: type: type == "regular") (builtins.readDir ./gen))
  );
  generatedByName = builtins.listToAttrs (
    map (
      fileName:
      lib.nameValuePair (lib.removeSuffix "-plugin.nix" fileName) (
        import (./gen + "/${fileName}") { inherit lib; }
      )
    ) generatedFileNames
  );
  prefixed = prefix: map (a: a // { message = "${prefix}: ${a.message}"; });
in
{
  config.assertions = lib.concatLists (
    lib.mapAttrsToList (
      pluginName: pluginCfg:
      if pluginCfg.enable && generatedByName ? ${pluginName} then
        let
          generated = generatedByName.${pluginName};
          optionPath = ''nixflix.navidrome.plugins."${pluginName}"'';
        in
        prefixed "${optionPath}.config" ((generated.mkAssertions or (_: [ ])) pluginCfg.config)
        ++ prefixed optionPath ((generated.mkPermissionAssertions or (_: [ ])) pluginCfg)
      else
        [ ]
    ) cfg.plugins
  );
}

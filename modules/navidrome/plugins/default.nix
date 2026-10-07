{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixflix.navidrome;

  navidromePlugins = import ./lib/navidrome-plugins.nix { inherit lib; };
  pluginsDefault = import ./firstClass.nix { inherit pkgs; };
in
{
  imports = [
    ./fromGenerated.nix
    ./pluginsService.nix
    ./lyrics-extra.nix
    ./assertions.nix
  ];

  options.nixflix.navidrome.plugins = lib.mkOption {
    description = ''
      Navidrome plugins to manage declaratively. Each key is a plugin's nixflix-facing
      name (usually, but not required to be, the same as its `pkgs.pkgsCross.wasi32.navidromePlugins`
      attribute name, e.g. "apple-music", "audiomuseai"). A default package and
      strongly-typed `config` sub-options are provided for some popular plugins.
    '';
    type = lib.types.submodule {
      freeformType = lib.types.attrsOf (navidromePlugins.mkPluginModule { enableDefault = false; });
    };
    default = pluginsDefault;
  };

  config = lib.mkMerge [
    {
      # First-class plugin packages; unconditional since gating on cfg.enable here would self-reference.
      nixflix.navidrome.plugins = pluginsDefault;
    }
    (lib.mkIf (config.nixflix.enable && cfg.enable) {
      services.navidrome.plugins = lib.mapAttrsToList (_: p: p.package) (
        lib.filterAttrs (_: p: p.enable && p.package != null) cfg.plugins
      );

      assertions = [
        {
          assertion = lib.all (p: p.package != null) (
            lib.attrValues (lib.filterAttrs (_: p: p.enable) cfg.plugins)
          );
          message = "nixflix.navidrome.plugins: every enabled plugin must have a `package` (check for a typo in the plugin name, or set `package` explicitly for a plugin not yet added to the first-class table in modules/navidrome/plugins/default.nix).";
        }
      ];
    })
  ];
}

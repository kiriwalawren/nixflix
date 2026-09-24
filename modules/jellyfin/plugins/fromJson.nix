{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.nixflix.jellyfin;
  jellyfinPlugins = import ../../../lib/jellyfin-plugins.nix { inherit lib; };
  buildJellyfinPlugin = import ../../../lib/build-jellyfin-plugin.nix { inherit pkgs; };
  selectVersions = import ./selectVersions.nix {
    inherit lib;
    jellyfinVersion = cfg.package.version;
  };
in
{
  options.nixflix.jellyfin.plugins =
    let
      pluginsJson = builtins.fromJSON (builtins.readFile ./plugins.json);

      pluginConfigs = {
        "Open Subtitles" = import ./openSubtitles.nix { inherit lib; };
        "subbuzz" = import ./subbuzz.nix { inherit lib; };
        "Subtitle Extract" = import ./subtitleExtract.nix { inherit lib; };
      };
    in
    builtins.mapAttrs (
      name: plugin:
      let
        versions = selectVersions plugin.versions;
        package =
          let
            version = if (versions == [ ]) then null else lib.lists.last versions;
          in
          if (version == null) then
            null
          else
            buildJellyfinPlugin {
              pname = lib.strings.sanitizeDerivationName name;
              inherit (version) version;
              src = pkgs.fetchzip {
                url = version.sourceUrl;
                inherit (version) hash;
                stripRoot = false;
              };
              passthru.pluginDirName = name;
              postInstall =
                let
                  metaJson = pkgs.writeText "jellyfin-plugin-meta-${lib.strings.sanitizeDerivationName name}.json" (
                    builtins.toJSON {
                      inherit (plugin)
                        category
                        description
                        guid
                        overview
                        owner
                        ;
                      inherit (version)
                        changelog
                        targetAbi
                        timestamp
                        version
                        ;
                      inherit name;
                      autoUpdate = false;
                    }
                  );
                in
                ''
                  cp ${metaJson} $out/meta.json
                '';
            };
      in
      lib.mkOption {
        type = jellyfinPlugins.mkPluginModule {
          packageDefault = package;
          configOption = pluginConfigs."${name}" or null;
        };
        default = { };
      }
    ) pluginsJson;
}

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

      # Target abi is always 4 components long, and Jellyfin Version needs to be the same length,
      # or versionAtLeast will return `false` despite the only difference in versions being the
      # number of segments.
      jellyfinVersion = lib.versions.pad 4 (lib.getVersion cfg.package);

      versionFilter =
        version:
        (lib.strings.versionAtLeast jellyfinVersion version.targetAbi)
        && (
          lib.strings.versionOlder jellyfinVersion "12" || lib.strings.versionAtLeast version.targetAbi "12"
        );
      selectVersion =
        versions:
        let
          filteredVersions = lib.sortOn (version: version.version) (builtins.filter versionFilter versions);
        in
        if ((builtins.length filteredVersions) == 0) then null else lib.lists.last filteredVersions;

    in
    builtins.mapAttrs (
      name: plugin:
      let
        version = selectVersion plugin.versions;
        package =
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

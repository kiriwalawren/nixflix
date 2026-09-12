{
  lib,
  pkgs,
  config,
  ...
}:
with lib;
let
  cfg = config.nixflix.jellyfin;
  jellyfinPlugins = import ../../../lib/jellyfin-plugins.nix { inherit lib; };
  buildJellyfinPlugin = import ../../../lib/build-jellyfin-plugin.nix { inherit pkgs; };
in
{
  options.nixflix.jellyfin.plugins =
    let
      pluginsJson = builtins.fromJSON (builtins.readFile ./plugins.json);
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
          filteredVersions = sortOn (version: version.version) (filter versionFilter versions);
        in
        if ((builtins.length filteredVersions) == 0) then null else lib.lists.last filteredVersions;

      pluginsToPackages =
        plugins:
        builtins.listToAttrs (
          lib.mapAttrsToList (
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
                      inherit (version) hash url;
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
                              imageUrl
                              overview
                              owner
                              ;
                            inherit (version) changelog targetAbi timestamp version;
                            inherit name;
                          }
                        );
                      in
                      ''
                        cp ${metaJson} $out/meta.json
                      '';
                  };
            in
            {
              inherit name;
              value = lib.mkOption {
                type = jellyfinPlugins.mkPluginModule {
                  packageDefault = package;
                };
                default = { };
              };
            }
          ) plugins
        );
    in
      /* mkOption {
        description = ''
          Jellyfin plugins to manage declaratively.

          Each key is the plugin name exactly as it appears in the Jellyfin
          repository manifest (e.g. "Anime", "Bookshelf", "Trakt"). Plugin names
          must be unique across all configured plugin repositories.

          Plugins are installed from `package`. This can either be a normal Nix
          derivation, or a repository lookup created with
          `nixflix.lib.jellyfinPlugins.fromRepo`.

          Plugin changes (installs, removals, version updates) cause Jellyfin to
          restart automatically. Plan plugin changes for maintenance windows to
          avoid interrupting active streams.
        '';
        type = types.submodule {
          freeformType = types.attrsOf (jellyfinPlugins.mkPluginModule { enableDefault = true; });
        };
        default = { };
        example = literalExpression ''
          {
            "Bookshelf" = {
              package = nixflix.lib.jellyfinPlugins.fromRepo {
                version = "13.0.0.0";
                hash = "sha256-16jaQRh1rIFE27nSSEWNF7UjVsPJDaRf24Ews0BZGas=";
              };
              config = {
                # Plain string (visible in Nix store)
                ComicVineApiKey = "my-api-key";
                # Or as a secret (read from file at activation time)
                # ComicVineApiKey._secret = "/run/secrets/comic-vine-api-key";
              };
            };

            "Intro Skipper" = {
              package = myJellyfinPlugin;
            };
          }
        '';
      }
    // */
    pluginsToPackages pluginsJson
    ;
}

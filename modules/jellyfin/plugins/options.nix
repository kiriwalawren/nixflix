{ lib, ... }:
with lib;
let
  jellyfinPlugins = import ../../../lib/jellyfin-plugins.nix { inherit lib; };
in
{
  options.nixflix.jellyfin.plugins = mkOption {
    description = ''
      Jellyfin plugins to manage declaratively.

      Each key is the plugin name exactly as it appears in the Jellyfin
      repository manifest (e.g. "Anime", "Comic Vine", "Trakt"). Plugin names
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
        "Comic Vine" = {
          package = nixflix.lib.jellyfinPlugins.fromRepo {
            version = "2.0.0.0";
            hash = "sha256-mpGs92mLaseab2OuWLuD0TpBuZ7VnJjAH6vTX5R9zAM=";
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
  };
}

{ lib, ... }:
with lib;
let
  pluginModule = types.submodule {
    freeformType = types.attrsOf types.anything;

    options = {
      version = mkOption {
        type = types.str;
        description = ''
          Version of the plugin to install (e.g. "14.0.0.0"). Must match a
          version available in the configured plugin repositories.
        '';
        example = "14.0.0.0";
      };

      enabled = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether this plugin should be installed. When false, the plugin is
          treated as absent: if it was previously installed by nixflix it will
          be uninstalled on the next nixos-rebuild. This is equivalent to
          removing the attribute entirely from nixflix.jellyfin.plugins.
        '';
      };
    };
  };
in
{
  options.nixflix.jellyfin.plugins = mkOption {
    description = ''
      Jellyfin plugins to manage declaratively via the Jellyfin API.

      Each key is the plugin name exactly as it appears in the Jellyfin
      repository manifest (e.g. "Anime", "Bookshelf", "Trakt"). Plugin names
      must be unique across all configured plugin repositories.

      Plugin changes (installs, removals, version updates) cause Jellyfin to
      restart automatically. Plan plugin changes for maintenance windows to
      avoid interrupting active streams.
    '';
    type = types.attrsOf pluginModule;
    default = { };
    example = literalExpression ''
      {
        "Bookshelf" = {
          # Plain string (visible in Nix store)
          ComicVineApiKey = "my-api-key";
          # Or as a secret (read from file at activation time)
          # ComicVineApiKey._secret = "/run/secrets/comic-vine-api-key";
        };
      }
    '';
  };
}

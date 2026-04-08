{ lib, ... }:
with lib;
let
  repoPackageSourceType = types.submodule {
    options = {
      version = mkOption {
        type = types.str;
        description = ''
          Version of the plugin to install. Use `"latest"` to resolve the
          newest version available in the pinned plugin manifest, or pin to a
          specific version (e.g. `"14.0.0.0"`) for reproducible deployments.
        '';
        example = "14.0.0.0";
      };

      hash = mkOption {
        type = types.str;
        description = ''
          Fixed-output hash for the unpacked plugin archive.
        '';
        example = "sha256-16jaQRh1rIFE27nSSEWNF7UjVsPJDaRf24Ews0BZGas=";
      };

      repository = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Optional repository name from `nixflix.jellyfin.system.pluginRepositories`.
          Leave unset to resolve by plugin name across all enabled repositories.
        '';
        example = "Jellyfin Stable";
      };
    };
  };

  pluginModule = types.submodule {
    options = {
      package = mkOption {
        type = types.nullOr (
          types.oneOf [
            types.package
            repoPackageSourceType
          ]
        );
        default = null;
        description = ''
          Nix package containing the unpacked Jellyfin plugin files to copy
          into Jellyfin's plugin directory.

          For repository-managed plugins, use
          `nixflix.lib.jellyfinPlugins.fromRepo { version = ...; hash = ...; }`
          to resolve a deterministic package from the pinned plugin manifests.
        '';
        example = literalExpression ''
          nixflix.lib.jellyfinPlugins.fromRepo {
            version = "13.0.0.0";
            hash = "sha256-16jaQRh1rIFE27nSSEWNF7UjVsPJDaRf24Ews0BZGas=";
          }
        '';
      };

      config = mkOption {
        type = types.attrsOf types.anything;
        default = { };
        description = ''
          Plugin configuration payload as seen in the Jellyfin UI/API. All
          attributes under this option are POSTed to
          `/Plugins/<id>/Configuration`.
        '';
        example = literalExpression ''
          {
            ComicVineApiKey._secret = "/run/secrets/comic-vine-api-key";
          }
        '';
      };

      enable = mkOption {
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
    type = types.attrsOf pluginModule;
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
  };
}

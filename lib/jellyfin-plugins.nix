{ lib, ... }:
let
  repoPackageSourceType = lib.types.submodule {
    options = {
      version = lib.mkOption {
        type = lib.types.str;
        description = ''
          Version of the plugin to install. Use `"latest"` to resolve the
          newest version available in the pinned plugin manifest, or pin to a
          specific version (e.g. `"14.0.0.0"`) for reproducible deployments.
        '';
        example = "14.0.0.0";
      };

      hash = lib.mkOption {
        type = lib.types.str;
        description = ''
          Fixed-output hash for the unpacked plugin archive.
        '';
        example = "sha256-16jaQRh1rIFE27nSSEWNF7UjVsPJDaRf24Ews0BZGas=";
      };

      repository = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Optional repository name from `nixflix.jellyfin.system.pluginRepositories`.
          Leave unset to resolve by plugin name across all enabled repositories.
        '';
        example = "Jellyfin Stable";
      };
    };
  };
in
{
  fromRepo =
    {
      version,
      hash,
      repository ? null,
    }:
    {
      inherit version hash repository;
    };

  packageModule = lib.mkOption {
    type = lib.types.nullOr (
      lib.types.oneOf [
        lib.types.package
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
    example = lib.literalExpression ''
      nixflix.lib.jellyfinPlugins.fromRepo {
        version = "13.0.0.0";
        hash = "sha256-16jaQRh1rIFE27nSSEWNF7UjVsPJDaRf24Ews0BZGas=";
      }
    '';
  };
}

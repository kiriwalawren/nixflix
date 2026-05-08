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

  mkPackageOption =
    default:
    lib.mkOption {
      inherit default;
      type = lib.types.nullOr (
        lib.types.oneOf [
          lib.types.package
          repoPackageSourceType
        ]
      );
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

  mkPluginModule =
    {
      enableDefault ? false,
      packageDefault ? null,
      configOption ? null,
    }:
    lib.types.submodule (
      { name, ... }:
      {
        options = {
          package = mkPackageOption packageDefault;

          config =
            if configOption == null then
              lib.mkOption {
                type = lib.types.attrsOf lib.types.anything;
                default = { };
                description = ''
                  Plugin configuration payload as seen in the Jellyfin UI/API. All
                  attributes under this option are POSTed to
                  `/Plugins/<id>/Configuration`.
                '';
                example = lib.literalExpression ''
                  {
                    ComicVineApiKey._secret = "/run/secrets/comic-vine-api-key";
                  }
                '';
              }
            else
              configOption;

          apiName = lib.mkOption {
            type = lib.types.str;
            default = name;
            description = ''
              The plugin's `Name` as reported by the Jellyfin `/Plugins` API.
              Defaults to the attribute name. Set this when the plugin's
              self-reported API name differs from its manifest name (e.g. the
              SSO-Auth plugin is listed in the manifest as `"SSO Authentication"`
              but reports itself via the API as `"SSO-Auth"`).

              Can be found when running the following while the plugin is installed:
              ```bash
              curl -s -H "Authorization: MediaBrowser Token=$(sudo cat /run/jellyfin/auth-token)" \
                                   http://127.0.0.1:8096/Plugins | jq '.[].Name'
              ```
            '';
            example = "SSO-Auth";
          };

          enable = lib.mkOption {
            type = lib.types.bool;
            default = enableDefault;
            description = ''
              Whether this plugin should be installed. When false, the plugin is
              treated as absent: if it was previously installed by nixflix it will
              be uninstalled on the next nixos-rebuild. This is equivalent to
              removing the attribute entirely from nixflix.jellyfin.plugins.
            '';
          };
        };
      }
    );
in
{
  inherit mkPluginModule;

  fromRepo =
    {
      version,
      hash,
      repository ? null,
    }:
    {
      inherit version hash repository;
    };
}

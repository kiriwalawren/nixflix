{ lib }:
rec {
  mkNonConfigOptions =
    {
      enableDefault ? false,
      apiIdDefault,
      packageDefault ? null,
    }:
    {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = enableDefault;
        description = ''
          Whether to install this plugin's package into `services.navidrome.plugins`
          and configure+enable it via the Navidrome API.
        '';
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = packageDefault;
        description = "Package producing this plugin's `.ndp` bundle.";
      };

      apiId = lib.mkOption {
        type = lib.types.str;
        default = apiIdDefault;
        description = "The plugin's `/api/plugin/<id>` id (its `.ndp` basename, when it differs from the attribute name).";
      };

      allLibraries = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "PUT as `allLibraries`.";
      };

      libraries = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "PUT as `libraries` (JSON-encoded) when `allLibraries = false`.";
      };

      allowWriteAccess = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "PUT as `allowWriteAccess`.";
      };
    };

  mkPluginModule =
    {
      enableDefault ? false,
    }:
    lib.types.submodule (
      { name, ... }:
      {
        options =
          (mkNonConfigOptions {
            inherit enableDefault;
            apiIdDefault = name;
          })
          // {
            config = lib.mkOption {
              type = lib.types.submodule {
                freeformType = lib.types.attrsOf lib.types.anything;
              };
              default = { };
              description = ''
                Plugin configuration. Strongly typed for plugins with a generated `./<name>-plugin.nix`, else freeform.

                When freeform, you can get the values from the web browser developer tools when changing the specified plugins settings.
              '';
            };
          };
      }
    );
}

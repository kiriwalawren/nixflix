{ lib }: rec {
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
        description = ''
          Package producing this plugin's `.ndp` bundle.

          For a plugin not packaged in nixpkgs (i.e. not available under
          `pkgs.pkgsCross.wasi32.navidromePlugins`), wrap its `.ndp` release asset in a minimal derivation.
          `passthru.isNavidromePlugin = true` is required, as `services.navidrome.plugins` only accepts packages
          carrying that flag. Navidrome installs the plugin under this derivation's `pname` (or `bundleName`), so
          `apiId` must match that same name.
        '';
        example = lib.literalExpression ''
          pkgs.stdenvNoCC.mkDerivation {
            pname = "discord-rpc-nd";
            version = "1.2.0";
            src = pkgs.fetchurl {
              url = "https://github.com/<owner>/<repo>/releases/download/v1.2.0/discord-rpc-nd.ndp";
              hash = "sha256-<ndp-hash>";
            };
            dontUnpack = true;
            installPhase = '''
              mkdir -p $out/share
              cp $src $out/share/discord-rpc-nd.ndp
            ''';
            passthru.isNavidromePlugin = true;
          }
        '';
      };

      apiId = lib.mkOption {
        type = lib.types.str;
        default = apiIdDefault;
        description = ''
          The plugin's `/api/plugin/<id>` id. This must equal the basename (without `.ndp`) of the file actually
          installed to `services.navidrome.finalPackage`'s plugin folder, i.e. `package`'s `pname` (or
          `bundleName`) — not necessarily this attribute's name. It defaults to the attribute name only as a
          convenience, for packages where the two happen to line up; set it explicitly whenever they don't (see
          the `discord-rich-presence`/`lyrics` first-class plugins for existing examples of this).
        '';
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
      { name, ... }: {
        options =
          (mkNonConfigOptions {
            inherit enableDefault;
            apiIdDefault = name;
          })
          // {
            config = lib.mkOption {
              type = lib.types.submodule { freeformType = lib.types.attrsOf lib.types.anything; };
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

{ lib, ... }:
let
  secrets = import ../../../lib/secrets { inherit lib; };

  jellyfinPlugins = import ../../../lib/jellyfin-plugins.nix { inherit lib; };
in
{
  options.nixflix.jellyfin.plugins."Open Subtitles" = lib.mkOption {
    type = jellyfinPlugins.mkPluginModule {
      packageDefault = jellyfinPlugins.fromRepo {
        version = "24.0.0.0";
        hash = "sha256-b6sgmgBlvhUAhFuq0p/EjB3604NGBkpS4NP33n1hfKc=";
      };

      configOption = lib.mkOption {
        type = lib.types.submodule {
          options = {
            CredentialsInvalid = lib.mkOption {
              type = lib.types.bool;
              default = false;
              internal = true;
              readOnly = true;
            };
            Username = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Username from OpenSubtitles.com";
            };
            Password = secrets.mkSecretOption {
              nullable = false;
              default = "";
              description = "Password for OpenSubtitles.com";
            };
          };
        };
        default = { };
        description = ''
          Open Subtitles plugin configuration payload as posted to the Jellyfin API.
          You can utilize this plugin by editing a library and modifying the options for subtitle downloads.
        '';
      };
    };
    default = { };
  };
}

{ lib, ... }:
with lib;
let
  secrets = import ../../../lib/secrets { inherit lib; };
in
{
  options.nixflix.aurral.settings.users = mkOption {
    type = types.attrsOf (
      types.submodule (
        { name, ... }: {
          options = {
            username = mkOption {
              type = types.str;
              default = name;
              example = "username";
              description = "Username for the user (used to login). Defaults to the attribute name.";
            };

            role = mkOption {
              type = types.enum [
                "admin"
                "user"
              ];
              default = "user";
              description = "Aurral role for this user.";
            };

            mutable = mkOption {
              type = types.bool;
              example = false;
              default = true;
              description = ''
                Functions like mutableUsers in NixOS users.users."user".
                If true, `role` and `permissions` are only applied when the user is created,
                and later changes from the Aurral UI take priority.
                If false, `role` and `permissions` are enforced on every rebuild.

                Note: Passwords are only set during user creation and are never updated
                declaratively, regardless of the mutable setting, because Aurral requires an
                interactive re-authentication to change another user's password. To change a
                user's password, use the Aurral web interface.
              '';
            };

            password = secrets.mkSecretOption {
              nullable = true;
              default = null;
              description = "User's password. Must be at least 8 characters. Required to create the user.";
            };

            permissions = mkOption {
              type = types.submodule {
                options = {
                  accessFlow = mkOption {
                    type = types.bool;
                    default = false;
                    description = "Whether the user can access the flow view.";
                  };

                  addArtist = mkOption {
                    type = types.bool;
                    default = true;
                    description = "Whether the user can add artists.";
                  };

                  addAlbum = mkOption {
                    type = types.bool;
                    default = true;
                    description = "Whether the user can add albums.";
                  };

                  changeMonitoring = mkOption {
                    type = types.bool;
                    default = false;
                    description = "Whether the user can change monitoring status.";
                  };

                  deleteArtist = mkOption {
                    type = types.bool;
                    default = false;
                    description = "Whether the user can delete artists.";
                  };

                  deleteAlbum = mkOption {
                    type = types.bool;
                    default = false;
                    description = "Whether the user can delete albums.";
                  };

                  deleteTrack = mkOption {
                    type = types.bool;
                    default = false;
                    description = "Whether the user can delete tracks.";
                  };
                };
              };
              default = { };
              description = "Per-user permissions, matching Aurral's user permissions schema.";
            };
          };
        }
      )
    );
    default = { };
    description = "Aurral users to declaratively manage via the admin API.";
  };
}

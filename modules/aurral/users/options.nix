{ lib, ... }:
with lib;
let
  secrets = import ../../../lib/secrets { inherit lib; };
in
{
  options.nixflix.aurral.users = mkOption {
    type = types.attrsOf (
      types.submodule {
        options = {
          userName = mkOption {
            type = types.str;
            example = "username";
            description = "Username for the user (used to login).";
          };

          email = mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "test@example.com";
            description = "The user's email.";
          };

          mutable = mkOption {
            type = types.bool;
            example = false;
            default = true;
            description = ''
              Functions like mutableUsers in NixOS users.users."user".
            '';
          };

          password = secrets.mkSecretOption {
            default = null;
            description = "User's password. Must be at least 12 characters.";
          };
        };
      }
    );
    default = { };
    description = "DroppedNeedle users to declaratively manage via the admin API.";
  };
}

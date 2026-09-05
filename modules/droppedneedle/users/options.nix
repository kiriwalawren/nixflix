{ lib, ... }:
with lib;
let
  secrets = import ../../../lib/secrets { inherit lib; };
in
{
  options.nixflix.droppedneedle.settings.users = mkOption {
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

          role = mkOption {
            type = types.enum [
              "admin"
              "trusted"
              "user"
            ];
            default = "user";
            description = "DroppedNeedle role for this user.";
          };

          mutable = mkOption {
            type = types.bool;
            example = false;
            default = true;
            description = ''
              Functions like mutableUsers in NixOS users.users."user".

              DroppedNeedle only exposes admin APIs to change a user's role and
              quota after creation; username, display name, email, and password
              are set once at creation and cannot be updated declaratively.

              If true, role and quota are only enforced the first time the user
              is created; any changes made afterwards through the DroppedNeedle
              web interface are left alone on subsequent rebuilds.
              If false, role and quota are reset to match this configuration on
              every rebuild, overriding any changes made through the web
              interface.
            '';
          };

          password = secrets.mkSecretOption {
            default = null;
            description = "User's password. Must be at least 12 characters.";
          };

          quota = {
            requestCount = mkOption {
              type = types.nullOr types.int;
              default = null;
              example = 20;
              description = "Maximum number of requests allowed in the quota window. Null inherits the global default; 0 is unlimited.";
            };

            requestDays = mkOption {
              type = types.nullOr types.int;
              default = null;
              example = 30;
              description = "Length in days of the request quota window. Null inherits the global default; 0 is unlimited.";
            };

            storageGb = mkOption {
              type = types.nullOr types.int;
              default = null;
              example = 100;
              description = "Maximum storage in GB this user's requests may consume. Null inherits the global default; 0 is unlimited.";
            };
          };
        };
      }
    );
    default = { };
    description = "DroppedNeedle users to declaratively manage via the admin API.";
  };
}

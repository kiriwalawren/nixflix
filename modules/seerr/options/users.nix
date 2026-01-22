{lib, ...}:
with lib; {
  options.nixflix.seerr.settings = {
    users = mkOption {
      type = types.submodule {
        options = {
          localLogin = mkOption {
            type = types.bool;
            default = true;
            description = "Enable local account authentication independent of Jellyfin/Plex";
          };

          mediaServerLogin = mkOption {
            type = types.bool;
            default = true;
            description = "Enable authentication via connected media server (Jellyfin/Plex)";
          };

          newPlexLogin = mkOption {
            type = types.bool;
            default = true;
            description = "Allow new Plex users to authenticate and create accounts";
          };

          defaultPermissions = mkOption {
            type = types.int;
            default = 32; # REQUEST permission
            description = ''
              Default permission flags for newly created users.
              Common values: 0 (none), 32 (REQUEST - default), 1024 (ADMIN)
            '';
          };

          defaultQuotas = mkOption {
            type = types.submodule {
              options = {
                movie = mkOption {
                  type = types.submodule {
                    options = {
                      quotaLimit = mkOption {
                        type = types.ints.unsigned;
                        default = 0;
                        description = "Max movie requests per period (0 = unlimited)";
                      };
                      quotaDays = mkOption {
                        type = types.ints.positive;
                        default = 7;
                        description = "Quota period in days";
                      };
                    };
                  };
                  default = {};
                };
                tv = mkOption {
                  type = types.submodule {
                    options = {
                      quotaLimit = mkOption {
                        type = types.ints.unsigned;
                        default = 0;
                        description = "Max TV requests per period (0 = unlimited)";
                      };
                      quotaDays = mkOption {
                        type = types.ints.positive;
                        default = 7;
                        description = "Quota period in days";
                      };
                    };
                  };
                  default = {};
                };
              };
            };
            default = {};
            description = "Default request quotas for new users";
          };
        };
      };
      default = {};
      defaultText = literalExpression ''
        {
          localLogin = true;
          mediaServerLogin = true;
          newPlexLogin = true;
          defaultPermissions = 32;
          defaultQuotas = {
            movie = { quotaLimit = 0; quotaDays = 7; };
            tv = { quotaLimit = 0; quotaDays = 7; };
          };
        }
      '';
      description = "Default user settings for Seerr (authentication, permissions, and quotas)";
    };
  };
}

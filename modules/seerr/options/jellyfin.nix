{
  config,
  lib,
  ...
}:
with lib;
let
  secrets = import ../../../lib/secrets { inherit lib; };
  jellyfinCfg = config.nixflix.jellyfin;
  adminUsers = filterAttrs (_: user: user.policy.isAdministrator) jellyfinCfg.users;
  sortedAdminNames = sort (a: b: a < b) (attrNames adminUsers);
  hasLocalAdmin = jellyfinCfg.enable && sortedAdminNames != [ ];
  firstAdminName = if hasLocalAdmin then head sortedAdminNames else null;
  firstAdminUser = if hasLocalAdmin then adminUsers.${firstAdminName} else null;
in
{
  options.nixflix.seerr.jellyfin = {
    adminUsername = mkOption {
      type = types.nullOr types.str;
      default = firstAdminName;
      defaultText = literalExpression "first admin username from nixflix.jellyfin.users, or null";
      description = ''
        Jellyfin admin username for Seerr authentication.

        Auto-derived from `nixflix.jellyfin.users` when Jellyfin is enabled locally.
        Must be set explicitly when using a remote Jellyfin instance.
      '';
    };

    adminPassword = secrets.mkSecretOption {
      default = if hasLocalAdmin then firstAdminUser.password else null;
      defaultText = literalExpression "password of first admin from nixflix.jellyfin.users, or null";
      description = ''
        Jellyfin admin password for Seerr authentication.

        Auto-derived from `nixflix.jellyfin.users` when Jellyfin is enabled locally.
        Must be set explicitly when using a remote Jellyfin instance.
      '';
    };

    hostname = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Jellyfin server hostname";
    };

    port = mkOption {
      type = types.port;
      default = config.nixflix.jellyfin.network.internalHttpPort or 8096;
      defaultText = literalExpression "config.nixflix.jellyfin.network.internalHttpPort";
      description = "Jellyfin server port";
    };

    useSsl = mkOption {
      type = types.bool;
      default = false;
      description = "Use SSL to connect to Jellyfin";
    };

    urlBase = mkOption {
      type = types.str;
      default =
        if config.nixflix.jellyfin.network.baseUrl == "" then
          ""
        else
          "/${config.nixflix.jellyfin.network.baseUrl}";
      description = "Jellyfin URL base";
    };

    externalHostname =
      let
        jellyfinBaseUrl =
          if config.nixflix.jellyfin.network.baseUrl == "" then
            ""
          else
            "/${config.nixflix.jellyfin.network.baseUrl}";
      in
      mkOption {
        type = types.str;
        default =
          if config.nixflix.nginx.enable then
            "${config.nixflix.seerr.externalUrlScheme}://${config.nixflix.jellyfin.subdomain}.${config.nixflix.nginx.domain}${jellyfinBaseUrl}"
          else
            "";
        defaultText = literalExpression ''
          if config.nixflix.nginx.enable != ""
          then "$${config.nixflix.seerr.externalUrlScheme}://$${config.nixflix.jellyfin.subdomain}.$${config.nixflix.nginx.domain}"
          else "";
        '';
      };

    serverType = mkOption {
      type = types.int;
      default = 2;
      description = "Server type (2 = Jellyfin)";
    };

    enableAllLibraries = mkOption {
      type = types.bool;
      default = true;
      description = "Enable all Jellyfin libraries (fetched from API). Set to false to use libraryFilter.";
    };

    libraryFilter = mkOption {
      type = types.submodule {
        options = {
          types = mkOption {
            type = types.listOf (
              types.enum [
                "movie"
                "show"
              ]
            );
            default = [ ];
            description = "Only enable libraries of these types (empty = all types)";
            example = [
              "movie"
              "show"
            ];
          };
          names = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Only enable libraries matching these names (empty = all names)";
            example = [
              "Movies"
              "TV Shows"
            ];
          };
        };
      };
      default = { };
      description = "Filter which libraries to enable (only used when enableAllLibraries = false)";
    };
  };
}

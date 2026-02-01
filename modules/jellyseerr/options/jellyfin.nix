{
  config,
  lib,
  ...
}:
with lib; {
  options.nixflix.jellyseerr.jellyfin = {
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
        if config.nixflix.nginx.enable
        then "/jellyfin"
        else "";
      defaultText = literalExpression ''if config.nixflix.nginx.enable then "/jellyfin" else ""'';
      description = "Jellyfin URL base";
    };

    externalHostname = mkOption {
      type = types.str;
      default =
        if config.nixflix.jellyseerr.externalBaseUrl != ""
        then "${config.nixflix.jellyseerr.externalBaseUrl}/${config.nixflix.jellyfin.network.baseUrl}"
        else "";
      defaultText = literalExpression ''
        if config.nixflix.jellyseerr.externalBaseUrl != ""
        then "$${config.nixflix.jellyseerr.externalBaseUrl}$${config.nixflix.jellyfin.network.baseUrl}"
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
            type = types.listOf (types.enum ["movie" "show"]);
            default = [];
            description = "Only enable libraries of these types (empty = all types)";
            example = ["movie" "show"];
          };
          names = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Only enable libraries matching these names (empty = all names)";
            example = ["Movies" "TV Shows"];
          };
        };
      };
      default = {};
      description = "Filter which libraries to enable (only used when enableAllLibraries = false)";
    };
  };
}

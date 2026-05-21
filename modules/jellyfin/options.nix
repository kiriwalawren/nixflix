{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  stateDir = "${config.nixflix.stateDir}/jellyfin";
  secrets = import ../../lib/secrets { inherit lib; };
in
{
  options.nixflix.jellyfin = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to enable Jellyfin media server";
    };

    apiKey = secrets.mkSecretOption {
      description = ''
        API key to inject into Jellyfin's database. Used by nixflix management services to authenticate to Jellyfin.

        Can be created with the following:

        ```bash
        openssl rand -hex 16
        ```
      '';
    };

    package = mkOption {
      type = types.package;
      default = pkgs.jellyfin;
      defaultText = literalExpression "pkgs.jellyfin";
      description = "Jellyfin package to use";
    };

    user = mkOption {
      type = types.str;
      default = "jellyfin";
      description = "User under which the service runs";
    };

    group = mkOption {
      type = types.str;
      default = config.nixflix.globals.libraryOwner.group;
      defaultText = literalExpression "config.nixflix.globals.libraryOwner.group";
      description = "Group under which the service runs";
    };

    dataDir = mkOption {
      type = types.path;
      default = stateDir;
      defaultText = literalExpression ''"''${config.nixflix.stateDir}/jellyfin"'';
      description = "Directory containing the Jellyfin data files";
    };

    configDir = mkOption {
      type = types.path;
      default = "${stateDir}/config";
      defaultText = literalExpression ''"''${config.nixflix.stateDir}/jellyfin/config"'';
      description = ''
        Directory containing the server configuration files,
        passed with `--configdir` see [configuration-directory](https://jellyfin.org/docs/general/administration/configuration/#configuration-directory)
      '';
    };

    cacheDir = mkOption {
      type = types.path;
      default = "/var/cache/jellyfin";
      description = ''
        Directory containing the jellyfin server cache,
        passed with `--cachedir` see [#cache-directory](https://jellyfin.org/docs/general/administration/configuration/#cache-directory)
      '';
    };

    logDir = mkOption {
      type = types.path;
      default = "${stateDir}/log";
      defaultText = literalExpression ''"''${config.nixflix.stateDir}/jellyfin/log"'';
      description = ''
        Directory where the Jellyfin logs will be stored,
        passed with `--logdir` see [#log-directory](https://jellyfin.org/docs/general/administration/configuration/#log-directory)
      '';
    };
  };
}

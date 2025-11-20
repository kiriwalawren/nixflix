{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  inherit (config) nixflix;
  inherit (config.nixflix) globals;
  stateDir = "${nixflix.stateDir}/jellyfin";
in {
  imports = [
    ./network.nix
    ./branding.nix
    ./encoding.nix
    ./system.nix
    ./users.nix
  ];
  options.nixflix.jellyfin = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to enable Jellyfin media server";
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
      default = globals.libraryOwner.group;
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

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Open ports in the firewall for Jellyfin.
        TCP ports 8096 and 8920, UDP ports 1900 and 7359.
      '';
    };

    vpn = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to route Jellyfin traffic through the VPN.
          When false (default), Jellyfin bypasses the VPN.
          When true, Jellyfin routes through the VPN (requires nixflix.mullvad.enable = true).
        '';
      };
    };

    apikeys = mkOption {
      description = ''
        API keys for Jellyfin.
        Each attribute name is the API key name, and the value is a path to a file containing the API key.
        The key must be a random GUID without dashes. To generate one, run:
        ```uuidgen -r | sed 's/-//g'```

        Note: At least the 'default' API key must be configured.
      '';
      default = {};
      type = types.attrsOf types.path;
      example = literalExpression ''
        {
          default = config.sops.secrets.jellyfin-default-key.path;
          Jellyseerr = config.sops.secrets.jellyfin-jellyseerr-key.path;
        }
      '';
    };
  };
}

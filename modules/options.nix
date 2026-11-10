{ config, lib, ... }:
with lib;
let
  cfg = config.nixflix;
in
{
  imports = [
    ./downloadarr
    ./flaresolverr.nix
    ./globals.nix
    ./jellyfin
    ./seerr
    ./lidarr
    ./postgres.nix
    ./prowlarr
    ./radarr.nix
    ./recyclarr
    ./sonarr-anime.nix
    ./sonarr.nix
    ./torrentClients
    ./usenetClients
    ./vpn.nix
  ];

  options.nixflix = {
    enable = mkEnableOption "Nixflix";

    serviceDependencies = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "unlock-raid.service"
        "tailscale.service"
      ];
      description = ''
        List of systemd services that nixflix services should wait for before starting.
        Useful for mounting encrypted drives, starting VPNs, or other prerequisites.
      '';
    };

    syncMode = mkOption {
      type = types.enum [
        "delete"
        "keep"
        "refuse"
      ];
      default = "delete";
      example = "refuse";
      description = ''
        What nixflix's sync units do with objects that exist in a service
        (root folders, profiles, indexers, download clients, ...) but are not
        declared in the nixflix configuration.

        - `"delete"`: remove undeclared objects, so the service matches the
          configuration exactly.
        - `"keep"`: create and update declared objects, never delete undeclared
          ones; the unit logs what it kept.
        - `"refuse"`: if undeclared objects exist, fail the unit before changing
          anything and list them, so they can be declared or removed by hand.

        This is the default for every collection. Override it per collection
        with `nixflix.<service>.syncMode.<collection>`.
      '';
    };

    theme = {
      enable = mkOption {
        type = types.bool;
        default = false;
        example = true;
        description = ''
          Enables themeing via [theme.park](https://docs.theme-park.dev/).
          Requires a reverse proxy (`nixflix.nginx.enable` or `nixflix.caddy.enable`) for all services except Jellyfin.
        '';
      };
      name = mkOption {
        type = types.str;
        default = "catppuccin-mocha";
        description = ''
          The name of any official theme or community theme supported by theme.park.

          - [Official Themes](https://docs.theme-park.dev/theme-options/)
          - [Community Themes](https://docs.theme-park.dev/community-themes/)
        '';
      };
    };

    reverseProxy = {
      enable = mkOption {
        type = types.bool;
        internal = true;
        readOnly = true;
        default = cfg.nginx.enable || cfg.caddy.enable;
        description = "Whether any reverse proxy is enabled (derived, not user-facing).";
      };

      domain = mkOption {
        type = types.str;
        internal = true;
        readOnly = true;
        default =
          if cfg.nginx.enable then
            cfg.nginx.domain
          else if cfg.caddy.enable then
            cfg.caddy.domain
          else
            "nixflix";
        description = "The active reverse proxy domain (derived).";
      };

      addHostsEntries = mkOption {
        type = types.bool;
        internal = true;
        readOnly = true;
        default =
          if cfg.nginx.enable then
            cfg.nginx.addHostsEntries
          else if cfg.caddy.enable then
            cfg.caddy.addHostsEntries
          else
            false;
        description = "Whether to add hosts entries (derived).";
      };

      forceSSL = mkOption {
        type = types.bool;
        internal = true;
        readOnly = true;
        default =
          if cfg.nginx.enable then
            cfg.nginx.forceSSL
          else if cfg.caddy.enable then
            cfg.caddy.tls.enable
          else
            false;
        description = "Whether SSL is forced (derived).";
      };

      httpScheme = mkOption {
        type = types.str;
        internal = true;
        readOnly = true;
        default =
          if cfg.reverseProxy.enable && (cfg.nginx.forceSSL || cfg.caddy.tls.enable) then "https" else "http";
        description = "The HTTP scheme to use for external URLs.";
      };
    };

    mediaUsers = mkOption {
      type = with types; listOf str;
      default = [ ];
      example = [ "user" ];
      description = ''
        Extra users to add to the media group.
      '';
    };

    mediaDir = mkOption {
      type = types.path;
      default = "/data/media";
      example = "/data/media";
      description = ''
        The location of the media directory for the services.

        !!! warning

            All parent directories must have execute permissions for everyone.

        !!! warning

            Setting this to any path, where the subpath is not owned by root, will fail! For example:

            ```nix
            mediaDir = /home/user/data
            ```

            Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    downloadsDir = mkOption {
      type = types.path;
      default = "/data/downloads";
      example = "/data/downloads";
      description = ''
        The location of the downloads directory for download clients.

        !!! warning

            All parent directories must have execute permissions for everyone.

        !!! warning

            Setting this to any path, where the subpath is not owned by root, will fail! For example:

            ```nix
            downloadsDir = /home/user/data
            ```

            Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib";
      example = "/data/.state";
      description = ''
        The location of the state directory for the services.

        !!! warning

            All parent directories must have execute permissions for everyone.

        !!! warning

            Setting this to any path, where the subpath is not owned by root, will fail! For example:

            ```nix
            stateDir = /home/user/data
            ```

            Is not supported, because `/home/user` is owned by `user`.
      '';
    };
  };
}

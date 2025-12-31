{
  config,
  lib,
  ...
}:
with lib; let
  inherit (config.nixflix) globals;
  cfg = config.nixflix;
in {
  imports = [
    ./globals.nix
    ./jellyfin
    ./jellyseerr
    ./lidarr.nix
    ./mullvad.nix
    ./postgres.nix
    ./prowlarr
    ./radarr.nix
    ./recyclarr
    ./sabnzbd
    ./sonarr.nix
    ./sonarr-anime.nix
  ];

  options.nixflix = {
    enable = mkEnableOption "Nixflix";

    serviceDependencies = mkOption {
      type = with types; listOf str;
      default = [];
      example = ["unlock-raid.service" "tailscale.service"];
      description = ''
        List of systemd services that nixflix services should wait for before starting.
        Useful for mounting encrypted drives, starting VPNs, or other prerequisites.
      '';
    };

    theme = {
      enable = mkEnableOption "Theme";
      name = mkOption {
        type = types.str;
        default = "overseerr";
        description = ''
          This is powered [theme.park](https://docs.theme-park.dev/).

          The name of any official theme or community theme supported by theme.park.

          - [Official Themes](https://docs.theme-park.dev/theme-options/)
          - [Community Themes](https://docs.theme-park.dev/community-themes/)
        '';
      };
    };

    nginx = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to enable nginx reverse proxy for all services";
      };
    };

    mediaUsers = mkOption {
      type = with types; listOf str;
      default = [];
      example = ["user"];
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

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        > mediaDir = /home/user/data
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    downloadsDir = mkOption {
      type = types.path;
      default = "/data/downloads";
      example = "/data/downloads";
      description = ''
        The location of the downloads directory for download clients.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        > downloadsDir = /home/user/downloads
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    stateDir = mkOption {
      type = types.path;
      default = "/data/.state";
      example = "/data/.state";
      description = ''
        The location of the state directory for the services.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        > stateDir = /home/user/data/.state
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };
  };

  config = mkIf cfg.enable {
    users.groups.media.members = cfg.mediaUsers;
    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}' 0755 root:root} - -"
      "d '${cfg.mediaDir}' 0775 ${globals.libraryOwner.user}:${globals.libraryOwner.group} - -"
      "d '${cfg.downloadsDir}' 0775 ${globals.libraryOwner.user}:${globals.libraryOwner.group} - -"
    ];

    services.nginx = mkIf cfg.nginx.enable {
      enable = true;

      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts.localhost = {
        serverName = "localhost";
        default = true;
        listen = [
          {
            addr = "0.0.0.0";
            port = 80;
          }
        ];
      };
    };
  };
}

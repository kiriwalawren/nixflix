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
    ./lidarr
    ./mullvad
    ./postgres
    ./prowlarr
    ./radarr
    ./recyclarr
    ./sabnzbd
    ./sonarr
  ];

  options.nixflix = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = "Whether or not to enable the nixflix module for Jellyfin media server stack";
    };

    serviceDependencies = mkOption {
      type = with types; listOf str;
      default = [];
      example = ["unlock-raid.service" "tailscale.service"];
      description = ''
        List of systemd services that nixflix services should wait for before starting.
        Useful for mounting encrypted drives, starting VPNs, or other prerequisites.
      '';
    };

    nginx = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to enable nginx reverse proxy for all services";
      };
    };

    serviceNameIsUrlBase = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to use the service name as the URL base (e.g., /sonarr, /radarr).
        When false, services will use "/" as the default URL base.
        When true, services will use "/{serviceName}" as the default URL base.
      '';
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
        >   mediaDir = /home/user/data
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
        >   downloadsDir = /home/user/downloads
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
        >   stateDir = /home/user/data/.state
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

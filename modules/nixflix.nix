{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  inherit (config.nixflix) globals;
  cfg = config.nixflix;
in {
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

    dirRegistrations = mkOption {
      type = with types;
        listOf (submodule {
          options = {
            dir = mkOption {
              type = path;
              description = "Directory path to create";
            };
            owner = mkOption {
              type = str;
              description = "Owner of the directory";
            };
            group = mkOption {
              type = str;
              description = "Group of the directory";
            };
            mode = mkOption {
              type = str;
              default = "0775";
              description = "Permission mode for the directory";
            };
          };
        });
      default = [];
      description = ''
        Directory registrations from services. Each service can register
        directories it needs to be created.
      '';
    };
  };

  config = mkIf cfg.enable {
    users.groups.media.members = cfg.mediaUsers;

    systemd.services.nixflix-setup-dirs = {
      description = "Create directories for nixflix media server services";
      wantedBy = ["multi-user.target"];
      after = cfg.serviceDependencies;
      requires = cfg.serviceDependencies;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        ${pkgs.coreutils}/bin/mkdir -p ${cfg.stateDir}
        ${pkgs.coreutils}/bin/chown root:root ${cfg.stateDir}
        ${pkgs.coreutils}/bin/chmod 0755 ${cfg.stateDir}

        ${pkgs.coreutils}/bin/mkdir -p ${cfg.mediaDir}
        ${pkgs.coreutils}/bin/chown ${globals.libraryOwner.user}:${globals.libraryOwner.group} ${cfg.mediaDir}
        ${pkgs.coreutils}/bin/chmod 0775 ${cfg.mediaDir}

        ${pkgs.coreutils}/bin/mkdir -p ${cfg.downloadsDir}
        ${pkgs.coreutils}/bin/chown ${globals.libraryOwner.user}:${globals.libraryOwner.group} ${cfg.downloadsDir}
        ${pkgs.coreutils}/bin/chmod 0775 ${cfg.downloadsDir}

        ${concatMapStringsSep "\n" (reg: ''
            ${pkgs.coreutils}/bin/mkdir -p ${reg.dir}
            ${pkgs.coreutils}/bin/chown ${reg.owner}:${reg.group} ${reg.dir}
            ${pkgs.coreutils}/bin/chmod ${reg.mode} ${reg.dir}
          '')
          cfg.dirRegistrations}
      '';
    };

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

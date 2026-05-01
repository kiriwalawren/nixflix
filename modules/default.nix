{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  inherit (config.nixflix) globals;
  cfg = config.nixflix;
in
{
  imports = [
    ./downloadarr
    ./flaresolverr.nix
    ./globals.nix
    ./jellyfin
    ./seerr
    ./lidarr.nix
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
        default = "overseerr";
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
    };

    nginx = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to enable nginx reverse proxy for all services";
      };

      domain = mkOption {
        type = types.str;
        default = "nixflix";
        example = "internal";
        description = "Base domain for subdomain-based reverse proxy routing. Each service is accessible at `<subdomain>.<domain>`.";
      };

      addHostsEntries = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to add `networking.hosts` entries mapping service subdomains to `127.0.0.1`.

          Enable if you don't have a separate DNS setup.
        '';
      };

      forceSSL = mkOption {
        type = types.bool;
        default = false;
        example = true;
        description = "Whether to force SSL.";
      };

      enableACME = mkOption {
        type = types.bool;
        default = false;
        example = true;
        description = ''
          Whether to enable `useACMEHost` in virtual hosts. Uses `nixflix.nginx.domain` as ACME host.

          You have to configure `security.acme.certs.$${nixflix.nginx.domain}` in order to use this.
        '';
      };
    };

    caddy = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to enable Caddy reverse proxy for all services.";
      };

      domain = mkOption {
        type = types.str;
        default = "nixflix";
        example = "internal";
        description = "Base domain for subdomain-based reverse proxy routing. Each service is accessible at `<subdomain>.<domain>`.";
      };

      addHostsEntries = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to add `networking.hosts` entries mapping service subdomains to `127.0.0.1`.

          Enable if you don't have a separate DNS setup.
        '';
      };

      tls = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Whether to enable TLS. Caddy handles ACME automatically when enabled with a public domain.
          '';
        };

        acmeEmail = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Email for ACME certificate registration. Required when using a public ACME provider.";
        };

        internal = mkOption {
          type = types.bool;
          default = false;
          description = "Use Caddy's internal (self-signed) CA instead of a public ACME provider. Useful for local/internal domains.";
        };
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
            mediaDir = /home/user/data
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
            mediaDir = /home/user/data
            ```

            Is not supported, because `/home/user` is owned by `user`.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.nginx.enable && cfg.caddy.enable);
        message = "nixflix.nginx.enable and nixflix.caddy.enable are mutually exclusive. Choose one reverse proxy.";
      }
    ];

    users.groups.media = {
      gid = globals.gids.media;
      members = cfg.mediaUsers;
    };

    systemd.tmpfiles.settings."10-nixflix" = {
      "${cfg.stateDir}".d = {
        mode = "0755";
        user = "root";
        group = "root";
      };
      "${cfg.mediaDir}".d = {
        mode = "0775";
        inherit (globals.libraryOwner) user;
        inherit (globals.libraryOwner) group;
      };
      "${cfg.downloadsDir}".d = {
        mode = "0775";
        inherit (globals.libraryOwner) user;
        inherit (globals.libraryOwner) group;
      };
    };

    systemd.services.nixflix-setup-dirs = {
      description = "Create tmp files";
      after = [ "systemd-tmpfiles-setup.service" ];
      requires = [ "systemd-tmpfiles-setup.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        ${pkgs.systemd}/bin/systemd-tmpfiles --create
      '';
    };

    services.nginx = mkIf cfg.nginx.enable {
      enable = true;
      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts."_" = {
        default = true;
        extraConfig = ''
          return 444;
        '';
      };
    };

    services.caddy = mkIf cfg.caddy.enable {
      enable = true;
      package = mkIf cfg.theme.enable (
        pkgs.caddy.withPlugins {
          plugins = [ "github.com/caddyserver/replace-response@v0.0.0-20250618171559-80962887e4c6" ];
          hash = "sha256-Li9eQjPeyOytfPdJXgtM3fh7qK/4WtgjmaweltQAk14=";
        }
      );
      globalConfig = ''
        ${optionalString (cfg.caddy.tls.acmeEmail != null) "email ${cfg.caddy.tls.acmeEmail}"}
      '';
    };
  };
}

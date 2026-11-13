{
  config,
  lib,
  options,
  ...
}:
with lib;
let
  inherit (import ../../lib/mkVirtualHosts.nix { inherit lib config; }) mkVirtualHost;
  secrets = import ../../lib/secrets { inherit lib; };
  getFirstAdmin = import ../../lib/getFirstAdmin.nix { inherit lib; };
  inherit (config.nixflix) jellyfin navidrome;
  cfg = config.nixflix.aurral;

  firstNavidromeAdmin =
    (getFirstAdmin {
      inherit (navidrome) users;
      isAdmin = user: user.isAdmin;
    }).user;
  hostname = "${cfg.subdomain}.${config.nixflix.reverseProxy.domain}";
in
{
  imports = [
    ./jellyfin.nix
    ./lidarr.nix
    ./navidrome.nix
    ./oidc.nix
    ./setupService.nix
    ./users
  ];

  options.nixflix.aurral = mkOption {
    type = types.submodule {
      freeformType = types.attrsOf types.anything;
      options = {
        enable = lib.mkEnableOption "Aurral is the Lidarr companion for self-hosted music discovery";

        user = mkOption {
          type = types.str;
          default = "aurral";
          description = "User under which Aurral runs.";
        };

        group = mkOption {
          type = types.str;
          default = config.nixflix.globals.libraryOwner.group;
          defaultText = literalExpression "config.nixflix.globals.libraryOwner.group";
          description = "Group under which Aurral runs.";
        };

        port = mkOption {
          type = types.port;
          default = 5030;
          description = "Port on which the Aurral web UI/API listens.";
        };

        directories = lib.mkOption {
          type = lib.types.listOf lib.types.externalPath;
          default = if config.nixflix.lidarr.enable then config.nixflix.lidarr.mediaDirs else [ ];
          description = ''
            Directories that Aurral needs access to. Other directories won't be visible by the app.
            Environment variable `DOWNLOAD_FOLDER` is added automatically.
            See BindPaths in {manpage}`systemd.exec(5)`.
          '';
        };

        dataDir = mkOption {
          type = types.path;
          default = "${config.nixflix.stateDir}/aurral";
          defaultText = literalExpression ''"''${nixflix.stateDir}/aurral"'';
          description = "Directory holding Aurral's data and configuration.";
        };

        libraryDir = mkOption {
          type = types.path;
          default = "${config.nixflix.mediaDir}/aurral";
          defaultText = literalExpression ''"''${config.nixflix.mediaDir}/aurral"'';
          description = ''
            Aurral's library root (its "Downloads Folder"). Downloads and imports land here,
            and it is added to the Navidrome and Jellyfin music libraries.
          '';
        };

        apiKey = secrets.mkSecretOption {
          description = ''
            API key for the Aurral API, passed to Aurral as `AURRAL_API_KEY`.
            Must be at least 32 characters.
          '';
        };

        subdomain = mkOption {
          type = types.str;
          default = "aurral";
          description = "Subdomain prefix for reverse proxy routing.";
        };

        vpn = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Whether to route Aurral traffic through the VPN.

              When `true`, Aurral is confined to the WireGuard network namespace
              (requires `nixflix.vpn.enable = true`).
            '';
          };

          namespace = mkOption {
            type = types.str;
            default = config.nixflix.vpn.namespace;
            defaultText = literalExpression "config.nixflix.vpn.namespace";
            description = "Name of the VPN network namespace to confine Aurral to when `vpn.enable = true`.";
          };
        };

        reverseProxy = {
          expose = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to expose the Aurral web UI via the reverse proxy.";
          };
        };

        settings = {
          lidarr = {
            url = mkOption {
              type = types.str;
              default = "http://${config.nixflix.lidarr.connectionAddress}:${toString config.nixflix.lidarr.config.hostConfig.port}${config.nixflix.lidarr.config.hostConfig.urlBase}";
              defaultText = literalExpression ''
                "http://''${config.nixflix.lidarr.connectionAddress}:''${toString config.nixflix.lidarr.config.hostConfig.port}''${config.nixflix.lidarr.config.hostConfig.urlBase}"
              '';
              description = "URL Aurral uses to connect to Lidarr. Only used when `nixflix.lidarr.enable = true`.";
            };

            apiKey = secrets.mkSecretOption {
              default = config.nixflix.lidarr.config.apiKey;
              defaultText = literalExpression "config.nixflix.lidarr.config.apiKey";
              description = "Lidarr API key used by Aurral. Only used when `nixflix.lidarr.enable = true`.";
            };

            defaultMonitorOption = mkOption {
              type = types.str;
              default = "none";
              description = "Default monitor option Aurral assigns to albums/artists added to Lidarr.";
            };

            searchOnAdd = mkOption {
              type = types.bool;
              default = false;
              description = "Whether Aurral should trigger a search when adding items to Lidarr.";
            };
          };

          jellyfin = {
            enable = mkOption {
              type = types.bool;
              default = jellyfin.enable && jellyfin.libraries.Music or null != null;
              defaultText = literalExpression "config.nixflix.jellyfin.enable && config.nixflix.jellyfin.libraries.Music or null != null";
              description = ''
                Whether to configure Aurral's Jellyfin integration, which tells Jellyfin to rescan
                the folders Aurral changes. Aurral only reports folders inside Jellyfin music libraries.
              '';
            };

            url = mkOption {
              type = types.str;
              default =
                "http://${jellyfin.connectionAddress}:${toString jellyfin.network.internalHttpPort}"
                + optionalString (jellyfin.network.baseUrl != "") "/${jellyfin.network.baseUrl}";
              defaultText = literalExpression ''
                "http://''${config.nixflix.jellyfin.connectionAddress}:''${toString config.nixflix.jellyfin.network.internalHttpPort}"
                + optionalString (config.nixflix.jellyfin.network.baseUrl != "") "/''${config.nixflix.jellyfin.network.baseUrl}"
              '';
              description = "URL Aurral uses to connect to Jellyfin. Only used when `enable = true`.";
            };

            apiKey = secrets.mkSecretOption {
              default = jellyfin.apiKey;
              defaultText = literalExpression "config.nixflix.jellyfin.apiKey";
              description = "Jellyfin API key used by Aurral. Only used when `enable = true`.";
            };

            userName = mkOption {
              type = types.str;
              default =
                (getFirstAdmin {
                  inherit (jellyfin) users;
                  isAdmin = user: user.policy.isAdministrator;
                }).name;
              defaultText = literalExpression "the alphabetically first user in config.nixflix.jellyfin.users with policy.isAdministrator = true";
              description = ''
                Jellyfin user Aurral acts as. Resolved to the user's ID at runtime.
                Only used when `enable = true`.
              '';
            };
          };

          navidrome = {
            enable = mkOption {
              type = types.bool;
              default = navidrome.enable;
              defaultText = literalExpression "config.nixflix.navidrome.enable";
              description = ''
                Whether to configure Aurral's Navidrome integration, which tells Navidrome to rescan
                the folders Aurral changes.
              '';
            };

            url = mkOption {
              type = types.str;
              default = "http://${navidrome.connectionAddress}:${toString navidrome.settings.Port}";
              defaultText = literalExpression ''"http://''${config.nixflix.navidrome.connectionAddress}:''${toString config.nixflix.navidrome.settings.Port}"'';
              description = "URL Aurral uses to connect to Navidrome. Only used when `enable = true`.";
            };

            username = mkOption {
              type = types.str;
              default = firstNavidromeAdmin.userName;
              defaultText = literalExpression "userName of the alphabetically first user in config.nixflix.navidrome.users with isAdmin = true";
              description = ''
                Navidrome user Aurral logs in as. Must be an admin, because only admins can start scans.
                Only used when `enable = true`.
              '';
            };

            password = secrets.mkSecretOption {
              default = firstNavidromeAdmin.password;
              defaultText = literalExpression "password of the alphabetically first user in config.nixflix.navidrome.users with isAdmin = true";
              description = "Password of `username`. Only used when `enable = true`.";
            };
          };

          security.localNetworkBypass.enabled = mkOption {
            type = types.bool;
            default = false;
            description = "Whether to bypass authentication for requests from the local network.";
          };
        };

        connectionAddress = mkOption {
          type = types.str;
          readOnly = true;
          default =
            if config.nixflix.vpn.enable && cfg.vpn.enable then
              config.vpnNamespaces.${cfg.vpn.namespace}.namespaceAddress
            else
              "127.0.0.1";
          description = "Address at which this service is reachable (derived).";
        };

        publicUrl = mkOption {
          type = types.str;
          readOnly = true;
          default = "${config.nixflix.reverseProxy.httpScheme}://${hostname}";
          defaultText = literalExpression ''"''${config.nixflix.reverseProxy.httpScheme}://''${hostname}"'';
          description = "Public URL used by Aurral for OAuth callbacks (derived).";
        };
      };
    };
    default = { };
    description = ''
      Aurral self-hosted music discovery and Lidarr companion app.

      Any option accepted by [`services.aurral`](https://search.nixos.org/options?channel=unstable&query=aurral&type=options)
      that isn't overridden above (e.g. `package`, `nginx`) can be set directly
      here too (e.g. `nixflix.aurral.package = ...;`) and is passed straight
      through.
    '';
  };

  config = lib.mkIf cfg.enable (mkMerge [
    (mkVirtualHost {
      inherit hostname;
      inherit (cfg.reverseProxy) expose;
      inherit (cfg) port;
      upstreamHost = cfg.connectionAddress;
      websocketUpgrade = true;
    })
    (optionalAttrs (options ? services.aurral) {
      services.aurral =
        (builtins.removeAttrs cfg [
          "apiKey"
          "connectionAddress"
          "libraryDir"
          "oidc"
          "publicUrl"
          "reverseProxy"
          "settings"
          "subdomain"
          "vpn"
        ])
        // {
          environment = {
            DOWNLOAD_FOLDER = cfg.libraryDir;
          }
          // optionalAttrs config.nixflix.reverseProxy.enable { AURRAL_PUBLIC_URL = cfg.publicUrl; };
        };
    })
    {
      assertions = [
        {
          assertion = lib.any (user: user.role == "admin") (lib.attrValues cfg.settings.users);
          message = "At least one Aurral user must have role = \"admin\".";
        }
        {
          assertion = secrets.isSecretRef cfg.apiKey || stringLength (trim cfg.apiKey) >= 32;
          message = "`nixflix.aurral.apiKey` must be at least 32 characters; Aurral refuses to start otherwise.";
        }
        {
          assertion = options ? services.aurral;
          message = "nixflix.aurral requires a nixpkgs that provides `services.aurral` (added to nixpkgs on 2026-09-09).";
        }
        {
          assertion =
            !(options ? services.aurral) || versionAtLeast config.services.aurral.package.version "2.13.0";
          message = "nixflix.aurral requires Aurral 2.13.0 or newer, but the Aurral package in use is ${config.services.aurral.package.version}. `nixflix.aurral.package` defaults to `pkgs.aurral` from your own nixpkgs rather than the nixpkgs nixflix pins. Update your nixpkgs, or set `nixflix.aurral.package` to a 2.13.0+ build.";
        }
      ];

      users = {
        users.${cfg.user} =
          mkForce {
            inherit (cfg) group;
            isSystemUser = true;
          }
          // optionalAttrs (config.nixflix.globals.uids ? ${cfg.user}) {
            uid = mkForce config.nixflix.globals.uids.${cfg.user};
          };

        groups.${cfg.group} = mkForce { };
      };

      systemd.tmpfiles.settings."10-aurral" = {
        ${cfg.dataDir}.d = {
          mode = "0750";
          inherit (cfg) user group;
        };
      };
    }
    {
      systemd.tmpfiles.settings."10-aurral"."/run/aurral".d = {
        mode = "0755";
        inherit (cfg) user group;
      };

      systemd.services.aurral-env = {
        description = "Create Aurral API key environment file";
        after = [ "nixflix-setup-dirs.service" ];
        requires = [ "nixflix-setup-dirs.service" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          set -euo pipefail
          cat > /run/aurral/api-key.env <<EOF
          AURRAL_API_KEY=${secrets.toShellValue cfg.apiKey}
          EOF
          chown ${cfg.user}:${cfg.group} /run/aurral/api-key.env
          chmod 0400 /run/aurral/api-key.env
        '';
      };

      systemd.services.aurral = {
        after = [ "aurral-env.service" ];
        requires = [ "aurral-env.service" ];
        serviceConfig.EnvironmentFile = [ "/run/aurral/api-key.env" ];
      };
    }
  ]);
}

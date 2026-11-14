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
  inherit (config.nixflix)
    jellyfin
    lidarr
    navidrome
    prowlarr
    slskd
    ;
  sabnzbd = config.nixflix.usenetClients.sabnzbd;
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
    ./lastfm.nix
    ./lidarr.nix
    ./navidrome.nix
    ./oidc.nix
    ./prowlarr.nix
    ./sabnzbd.nix
    ./setupService.nix
    ./slskd.nix
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
          default = 3001;
          description = "Port on which the Aurral web UI/API listens.";
        };

        directories = lib.mkOption {
          type = lib.types.listOf lib.types.externalPath;
          default =
            optionals lidarr.enable lidarr.mediaDirs
            ++ optional cfg.settings.slskd.enable slskd.settings.directories.downloads
            ++ optional cfg.settings.sabnzbd.enable sabnzbd.settings.misc.complete_dir;
          defaultText = literalExpression ''
            optionals config.nixflix.lidarr.enable config.nixflix.lidarr.mediaDirs
            ++ optional config.nixflix.aurral.settings.slskd.enable config.nixflix.slskd.settings.directories.downloads
            ++ optional config.nixflix.aurral.settings.sabnzbd.enable config.nixflix.usenetClients.sabnzbd.settings.misc.complete_dir
          '';
          description = ''
            Directories that Aurral needs access to. Other directories are read-only to the app.
            Environment variable `DOWNLOAD_FOLDER` is added automatically.
            Aurral removes completed slskd and SABnzbd downloads after importing them, so their
            download folders must be listed here.
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
          default = "${config.nixflix.mediaDir}/music";
          defaultText = literalExpression ''"''${config.nixflix.mediaDir}/music"'';
          description = ''
            Aurral's library root (its "Downloads Folder"). Downloads and imports land here,
            and it is added to the Navidrome and Jellyfin music libraries.
            While Lidarr is enabled with this folder as a root folder, Aurral treats every file
            in it as Lidarr's and never deletes it.
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
              default = true;
              description = "Whether Aurral should trigger a search when adding items to Lidarr.";
            };

            externalUrl = mkOption {
              type = types.str;
              default =
                optionalString (config.nixflix.reverseProxy.enable && lidarr.reverseProxy.expose)
                  "${config.nixflix.reverseProxy.httpScheme}://${lidarr.subdomain}.${config.nixflix.reverseProxy.domain}";
              defaultText = literalExpression ''
                optionalString (config.nixflix.reverseProxy.enable && config.nixflix.lidarr.reverseProxy.expose)
                  "''${config.nixflix.reverseProxy.httpScheme}://''${config.nixflix.lidarr.subdomain}.''${config.nixflix.reverseProxy.domain}"
              '';
              description = "Lidarr URL used for links in the Aurral UI. Empty means `url` is used.";
            };

            rootFolderPath = mkOption {
              type = types.nullOr types.str;
              default = if lidarr.config.rootFolders == [ ] then null else (head lidarr.config.rootFolders).path;
              defaultText = literalExpression "(head config.nixflix.lidarr.config.rootFolders).path, or null when there are none";
              description = "Lidarr root folder Aurral adds artists to. Left unchanged when null.";
            };
          };

          prowlarr = {
            enable = mkOption {
              type = types.bool;
              default = prowlarr.enable;
              defaultText = literalExpression "config.nixflix.prowlarr.enable";
              description = "Whether to configure Aurral's Prowlarr integration, used to search Usenet indexers.";
            };

            url = mkOption {
              type = types.str;
              default = "http://${prowlarr.connectionAddress}:${toString prowlarr.config.hostConfig.port}${prowlarr.config.hostConfig.urlBase}";
              defaultText = literalExpression ''
                "http://''${config.nixflix.prowlarr.connectionAddress}:''${toString config.nixflix.prowlarr.config.hostConfig.port}''${config.nixflix.prowlarr.config.hostConfig.urlBase}"
              '';
              description = "URL Aurral uses to connect to Prowlarr. Only used when `enable = true`.";
            };

            apiKey = secrets.mkSecretOption {
              nullable = true;
              default = prowlarr.config.apiKey;
              defaultText = literalExpression "config.nixflix.prowlarr.config.apiKey";
              description = "Prowlarr API key used by Aurral. Only used when `enable = true`.";
            };

            categories = mkOption {
              type = types.listOf types.ints.positive;
              default = [ 3000 ];
              description = "Newznab categories Aurral searches in Prowlarr. 3000 is Audio.";
            };
          };

          sabnzbd = {
            enable = mkOption {
              type = types.bool;
              default = sabnzbd.enable;
              defaultText = literalExpression "config.nixflix.usenetClients.sabnzbd.enable";
              description = "Whether to configure Aurral's SABnzbd integration, used to download from Usenet.";
            };

            url = mkOption {
              type = types.str;
              default = "http://${sabnzbd.connectionAddress}:${toString sabnzbd.settings.misc.port}${sabnzbd.settings.misc.url_base}";
              defaultText = literalExpression ''
                "http://''${config.nixflix.usenetClients.sabnzbd.connectionAddress}:''${toString config.nixflix.usenetClients.sabnzbd.settings.misc.port}''${config.nixflix.usenetClients.sabnzbd.settings.misc.url_base}"
              '';
              description = "URL Aurral uses to connect to SABnzbd. Only used when `enable = true`.";
            };

            apiKey = secrets.mkSecretOption {
              nullable = true;
              default = sabnzbd.settings.misc.api_key;
              defaultText = literalExpression "config.nixflix.usenetClients.sabnzbd.settings.misc.api_key";
              description = "SABnzbd API key used by Aurral. Only used when `enable = true`.";
            };

            category = mkOption {
              type = types.str;
              default = "aurral";
              description = ''
                SABnzbd category Aurral downloads into. nixflix adds an `aurral` category to
                SABnzbd by default.
              '';
            };
          };

          slskd = {
            enable = mkOption {
              type = types.bool;
              default = slskd.enable;
              defaultText = literalExpression "config.nixflix.slskd.enable";
              description = "Whether to configure Aurral's slskd integration, used to download from Soulseek.";
            };

            url = mkOption {
              type = types.str;
              default = "http://${slskd.connectionAddress}:${toString slskd.settings.web.port}";
              defaultText = literalExpression ''"http://''${config.nixflix.slskd.connectionAddress}:''${toString config.nixflix.slskd.settings.web.port}"'';
              description = "URL Aurral uses to connect to slskd. Only used when `enable = true`.";
            };

            apiKey = secrets.mkSecretOption {
              nullable = true;
              default = slskd.apiKey;
              defaultText = literalExpression "config.nixflix.slskd.apiKey";
              description = "slskd API key used by Aurral. Only used when `enable = true`.";
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

          lastfm = {
            apiKey = secrets.mkSecretOption {
              nullable = true;
              description = ''
                Last.fm API key, shown under Settings → Discovery → Last.fm. Aurral uses it for
                recommendations and falls back to ListenBrainz without it.
                Leaving it null clears the stored key.
              '';
            };

            apiSecret = secrets.mkSecretOption {
              nullable = true;
              description = ''
                Last.fm shared secret, shown under Settings → Discovery → Last.fm. Only needed for
                scrobbling. Requires `apiKey`.
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

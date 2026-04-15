{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  cfg = config.nixflix.torrentClients.qbittorrent;
  service = config.services.qbittorrent;

  hostname = "${cfg.subdomain}.${config.nixflix.nginx.domain}";
  categoriesJson = builtins.toJSON (lib.mapAttrs (_name: path: { save_path = path; }) cfg.categories);
  categoriesFile = pkgs.writeText "categories.json" categoriesJson;
  configPath = "${service.profileDir}/qBittorrent/config";
in
{
  options.nixflix.torrentClients.qbittorrent = mkOption {
    type = types.submodule {
      freeformType = types.attrsOf types.anything;
      options = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Whether to enable qBittorrent usenet downloader.

            Uses all of the same options as [nixpkgs qBittorent](https://search.nixos.org/options?channel=unstable&query=qbittorrent).
          '';
        };

        user = mkOption {
          type = types.str;
          default = "qbittorrent";
          description = "User account under which qbittorrent runs.";
        };

        group = mkOption {
          type = types.str;
          default = config.nixflix.globals.libraryOwner.group;
          description = "Group under which qbittorrent runs.";
        };

        downloadsDir = mkOption {
          type = types.str;
          default = "${config.nixflix.downloadsDir}/torrent";
          defaultText = literalExpression ''"$${config.nixflix.downloadsDir}/torrent"'';
          description = "Base directory for qBittorrent downloads";
        };

        vpn = {
          enable = mkOption {
            type = types.bool;
            default = config.nixflix.vpn.enable;
            defaultText = literalExpression "config.nixflix.vpn.enable";
            description = ''
              Whether to route qBittorrent traffic through the VPN.

              When `false`, qBittorrent bypasses the VPN.
              When `true`, qBittorrent is confined to the WireGuard network namespace (requires nixflix.vpn.enable = true).
            '';
          };
        };

        categories = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default =
            let
              getCategory =
                service:
                lib.optionalString (config.nixflix.${service}.enable or false) "${cfg.downloadsDir}/${service}";
            in
            {
              radarr = getCategory "radarr";
              sonarr = getCategory "sonarr";
              sonarr-anime = getCategory "sonarr-anime";
              lidarr = getCategory "lidarr";
              prowlarr = getCategory "prowlarr";
            };
          defaultText = lib.literalExpression ''
            {
              radarr = lib.optionalString (config.nixflix.radarr.enable or false) "${cfg.downloadsDir}/radarr";
              sonarr = lib.optionalString (config.nixflix.radarr.enable or false) "${cfg.downloadsDir}/sonarr";
              sonarr-anime = lib.optionalString (config.nixflix.radarr.enable or false) "${cfg.downloadsDir}/sonarr-anime";
              lidarr = lib.optionalString (config.nixflix.radarr.enable or false) "${cfg.downloadsDir}/lidarr";
              prowlarr = lib.optionalString (config.nixflix.radarr.enable or false) "${cfg.downloadsDir}/prowlarr";
            }
          '';
          description = "Map of category names to their save paths (relative or absolute).";
          example = {
            prowlarr = "games";
            sonarr = "/mnt/share/movies";
          };
        };

        webuiPort = mkOption {
          type = types.nullOr types.port;
          default = 8282;
          description = "the port passed to qbittorrent via `--webui-port`";
        };

        password = secrets.mkSecretOption {
          description = ''
            The password for qbittorrent. This is for the other services to integrate with qBittorrent.
            Not for setting the password in qBittorrent

            In order to set the password for qBittorrent itself, you will need to configure
            `nixflix.torrentClients.qbittorrent.serverConfig.Preferences.WebUI.Password_PBKDF2`. Look at the
            [serverConfig documentation](https://search.nixos.org/options?channel=unstable&query=qbittorrent&show=services.qbittorrent.serverConfig)
            to see how to configure it.
          '';
        };

        subdomain = mkOption {
          type = types.str;
          default = "qbittorrent";
          description = "Subdomain prefix for nginx reverse proxy.";
        };

        serverConfig = {
          BitTorrent.Session = {
            DefaultSavePath = mkOption {
              type = types.str;
              default = "${cfg.downloadsDir}/default";
              defaultText = literalExpression ''"''${config.nixflix.torrentClients.qbittorrent.downloadsDir}/default"'';
              description = "Default save path for downloads without a category.";
            };

            DisableAutoTMMByDefault = mkOption {
              type = types.bool;
              default = false;
              description = ''
                Default Torrent Management Mode. Set to false to enable category save paths.

                `true` = `Manual`, `false` = `Automatic`
              '';
            };
          };

          Preferences.WebUI.Address = mkOption {
            type = types.str;
            default = "127.0.0.1";
            description = "Bind address for the WebUI";
          };
        };
      };
    };
    default = { };
  };

  config = mkMerge [
    (mkIf (config.nixflix.enable && cfg != null && cfg.enable) {
      assertions = [
        {
          assertion = cfg.vpn.enable -> config.nixflix.vpn.enable;
          message = "Cannot enable VPN routing for qBittorrent (nixflix.seerr.vpn.enable = true) when VPN is not enabled. Please set nixflix.vpn.enable = true.";
        }
      ];

      services.qbittorrent = builtins.removeAttrs cfg [
        "categories"
        "downloadsDir"
        "password"
        "subdomain"
        "vpn"
      ];

      users = {
        # nixpkgs' `service.qbittorrent.[user|group]` only gets created
        # when the value is "qbittorent", so we create it here
        users.${service.user} = mkForce {
          inherit (service) group;
          isSystemUser = true;
          uid = config.nixflix.globals.uids.qbittorrent;
        };

        groups.${service.group} = mkForce { };
      };

      systemd.tmpfiles = {
        settings."10-qbittorrent" = {
          ${service.profileDir}.d = {
            inherit (service) user group;
            mode = "0755";
          };
          ${configPath}.d = {
            inherit (service) user group;
            mode = "0754";
          };
          ${cfg.downloadsDir}.d = {
            inherit (service) user group;
            mode = "0775";
          };
          ${cfg.serverConfig.BitTorrent.Session.DefaultSavePath}.d = {
            inherit (service) user group;
            mode = "0775";
          };
        }
        // lib.mapAttrs' (
          _name: path:
          lib.nameValuePair path {
            d = {
              inherit (service) user group;
              mode = "0775";
            };
          }
        ) (lib.filterAttrs (_name: path: path != "") cfg.categories);
      };

      systemd.services.qbittorrent = {
        after = [ "nixflix-setup-dirs.service" ];
        requires = [ "nixflix-setup-dirs.service" ];
        preStart = lib.mkIf (cfg.categories != { }) (
          lib.mkAfter ''
            cp -f '${categoriesFile}' '${configPath}/categories.json'
            chmod 640 '${configPath}/categories.json'
            chown ${service.user}:${service.group} '${configPath}/categories.json'
          ''
        );
      };

      networking.hosts = mkIf (config.nixflix.nginx.enable && config.nixflix.nginx.addHostsEntries) {
        "127.0.0.1" = [ hostname ];
      };

      services.nginx.virtualHosts."${hostname}" = mkIf config.nixflix.nginx.enable {
        inherit (config.nixflix.nginx) forceSSL;
        useACMEHost = if config.nixflix.nginx.enableACME then config.nixflix.nginx.domain else null;

        locations."/" = {
          proxyPass = "http://${
            if config.nixflix.vpn.enable then config.vpnNamespaces.wg.namespaceAddress else "127.0.0.1"
          }:${toString service.webuiPort}";
          recommendedProxySettings = true;
          extraConfig = ''
            proxy_http_version 1.1;

            ${
              if config.nixflix.theme.enable then
                ''
                  proxy_set_header Accept-Encoding "";
                  proxy_hide_header "x-webkit-csp";
                  proxy_hide_header "content-security-policy";
                  proxy_hide_header "X-Frame-Options";

                  sub_filter '</body>' '<link rel="stylesheet" type="text/css" href="https://theme-park.dev/css/base/qbittorrent/${config.nixflix.theme.name}.css"></body>';
                  sub_filter_once on;
                ''
              else
                ""
            }
          '';
        };
      };

    })
    (mkIf (config.nixflix.enable && cfg.enable && config.nixflix.vpn.enable && cgf.vpn.enable) {
      systemd.services.qbittorrent.vpnConfinement = {
        enable = true;
        vpnNamespace = "wg";
      };
      vpnNamespaces.wg.portMappings = [
        {
          from = service.webuiPort;
          to = service.webuiPort;
          protocol = "tcp";
        }
      ];
    })
  ];
}

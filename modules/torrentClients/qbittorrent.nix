{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  inherit (import ../../lib/mkVirtualHosts.nix { inherit lib config; }) mkVirtualHost;
  cfg = config.nixflix.torrentClients.qbittorrent;
  service = config.services.qbittorrent;

  hostname = "${cfg.subdomain}.${config.nixflix.reverseProxy.domain}";
  categoriesJson = builtins.toJSON (lib.mapAttrs (_name: path: { save_path = path; }) cfg.categories);
  categoriesFile = pkgs.writeText "categories.json" categoriesJson;
  configPath = "${service.profileDir}/qBittorrent/config";

  syncMode = import ../../lib/sync-mode.nix { inherit lib pkgs; };
  jq = "${pkgs.jq}/bin/jq";
  categoriesMode = cfg.syncMode.categories;

  writeCategories = ''
    cp -f '${categoriesFile}' '${configPath}/categories.json'
    chmod 640 '${configPath}/categories.json'
    chown ${service.user}:${service.group} '${configPath}/categories.json'
  '';

  categories = syncMode.mkPrune {
    mode = categoriesMode;
    unit = "qbittorrent";
    what = "categories";
    option = "nixflix.torrentClients.qbittorrent.syncMode.categories";
    live = "NIXFLIX_LIVE_CATEGORIES";
    declared = attrNames cfg.categories;
    id = ".save_path";
    onDelete = "";
  };

  # categories.json as a JSON array of { name, save_path }, `[]` when the file
  # is missing or empty, `null` when it is not a JSON object.
  readLiveCategories = ''
    NIXFLIX_CATEGORIES_FILE='${configPath}/categories.json'
    if [ -e "$NIXFLIX_CATEGORIES_FILE" ]; then
      NIXFLIX_LIVE_CATEGORIES=$(${jq} -cs 'if . == [] then [] elif (.[0] | type) == "object" then .[0] | to_entries | map({ name: .key, save_path: ((.value | objects | .save_path) // .value | tostring) }) else null end' "$NIXFLIX_CATEGORIES_FILE" 2>/dev/null) || NIXFLIX_LIVE_CATEGORIES=null
    else
      NIXFLIX_LIVE_CATEGORIES='[]'
    fi
  '';

  syncCategories =
    {
      delete = writeCategories;

      # Existing categories first, so the declared save paths win.
      keep = ''
        ${readLiveCategories}
        ${categories.prune}
        if [ "$NIXFLIX_LIVE_CATEGORIES" != null ] && [ -s "$NIXFLIX_CATEGORIES_FILE" ]; then
          ${jq} -s --slurpfile declared '${categoriesFile}' '.[0] * $declared[0]' "$NIXFLIX_CATEGORIES_FILE" > "$NIXFLIX_CATEGORIES_FILE.nixflix-tmp"
          mv -f "$NIXFLIX_CATEGORIES_FILE.nixflix-tmp" "$NIXFLIX_CATEGORIES_FILE"
        else
          if [ "$NIXFLIX_LIVE_CATEGORIES" = null ]; then
            echo "nixflix: qbittorrent: categories.json is not a JSON object; replacing it with the declared categories" >&2
          fi
          cp -f '${categoriesFile}' "$NIXFLIX_CATEGORIES_FILE"
        fi
        chmod 640 "$NIXFLIX_CATEGORIES_FILE"
        chown ${service.user}:${service.group} "$NIXFLIX_CATEGORIES_FILE"
      '';

      refuse = ''
        ${readLiveCategories}
        ${categories.guard}
        ${syncMode.refuseCheckpoint}
        ${writeCategories}
      '';
    }
    .${categoriesMode};
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

        syncMode.categories =
          let
            option = syncMode.mkModeOption {
              inherit config;
              what = "categories";
              collectionOption = "nixflix.torrentClients.qbittorrent.categories";
            };
          in
          option
          // {
            description = option.description + ''

              Applied to `categories.json` in the `preStart` of
              `qbittorrent.service` itself, so `"refuse"` stops qBittorrent from
              starting (exit code 78) until the undeclared categories are
              declared or removed. `"delete"` replaces the file with the
              declared categories; `"keep"` merges the declared categories into
              it, declared save paths winning.
            '';
          };

        webuiPort = mkOption {
          type = types.nullOr types.port;
          default = 8282;
          description = "the port passed to qbittorrent via `--webui-port`";
        };

        password = secrets.mkSecretOption {
          nullable = true;
          description = ''
            The password for qbittorrent. This is for the other services to integrate with qBittorrent.
            Not for setting the password in qBittorrent

            In order to set the password for qBittorrent itself, you will need to configure
            `nixflix.torrentClients.qbittorrent.serverConfig.Preferences.WebUI.Password_PBKDF2`.
            You can create a hash of your password with: `nix run git+https://codeberg.org/feathecutie/qbittorrent_password -- --password 'plain-text-password-here'`.

            Then set `nixflix.torrentClients.qbittorrent.serverConfig.Preferences.WebUI.Password_PBKDF2 = "@ByteArray(output-from-above-command)"`

            Further explanation can be found at the
            [serverConfig documentation](https://search.nixos.org/options?channel=unstable&query=qbittorrent&type=options#show=option%253Aservices.qbittorrent.serverConfig).
          '';
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

              !!! warning "Port forwarding is your responsibility"

                  Once qBittorrent is confined to the VPN, any port forwarding you have configured
                  on your router (WAN) no longer reaches it, because incoming connections now arrive
                  through the VPN tunnel instead. Without an open port, qBittorrent can still download,
                  but it cannot accept incoming peer connections, which reduces the number of peers
                  you can connect to.

                  To restore incoming connections, you must use a VPN provider that supports port
                  forwarding and configure it yourself. Nixflix does not manage this for you.

                  Some providers, such as ProtonVPN, assign a random forwarded port that must be
                  periodically renewed with NAT-PMP and then set as qBittorrent's listening port.
                  For an example of how to automate this with ProtonVPN, see
                  the [VPN Port Forwarding example](../../../examples/vpn-port-forwarding.md).
            '';
          };

          namespace = mkOption {
            type = types.str;
            default = config.nixflix.vpn.namespace;
            defaultText = literalExpression "config.nixflix.vpn.namespace";
            description = "Name of the VPN network namespace to confine qBittorrent to when `vpn.enable = true`.";
          };
        };

        subdomain = mkOption {
          type = types.str;
          default = "qbittorrent";
          description = "Subdomain prefix for reverse proxy.";
        };

        reverseProxy = {
          expose = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to expose qBittorrent via the reverse proxy.";
          };
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
            default =
              if config.nixflix.vpn.enable && cfg.vpn.enable then
                config.vpnNamespaces.${cfg.vpn.namespace}.namespaceAddress
              else
                "127.0.0.1";
            defaultText = literalExpression ''
              if config.nixflix.vpn.enable && config.nixflix.torrentClients.qbittorrent.vpn.enable
              then config.vpnNamespaces.$${config.nixflix.torrentClients.qbittorrent.vpn.namespace}.namespaceAddress
              else "127.0.0.1"
            '';
            description = "Bind address for the WebUI";
          };
        };

        connectionAddress = mkOption {
          type = types.str;
          readOnly = true;
          default =
            if cfg.serverConfig.Preferences.WebUI.Address == "*" then
              "127.0.0.1"
            else
              cfg.serverConfig.Preferences.WebUI.Address;
          description = "Address for connecting to this service.";
        };
      };
    };
    default = { };
  };

  config = mkIf (config.nixflix.enable && cfg != null && cfg.enable) (mkMerge [
    (mkVirtualHost {
      inherit hostname;
      inherit (cfg.reverseProxy) expose;
      port = service.webuiPort;
      upstreamHost = cfg.connectionAddress;
      themeParkService = "qbittorrent";
      stripHeaders = [
        "x-webkit-csp"
        "content-security-policy"
        "X-Frame-Options"
      ];
    })
    {
      assertions = [
        {
          assertion = cfg.vpn.enable -> config.nixflix.vpn.enable;
          message = "Cannot enable VPN routing for qBittorrent (nixflix.torrentClients.qbittorrent.vpn.enable = true) when VPN is not enabled. Please set nixflix.vpn.enable = true.";
        }
      ];

      services.qbittorrent = builtins.removeAttrs cfg [
        "categories"
        "connectionAddress"
        "downloadsDir"
        "password"
        "reverseProxy"
        "subdomain"
        "syncMode"
        "vpn"
      ];

      users = {
        # nixpkgs' `service.qbittorrent.[user|group]` only gets created
        # when the value is "qbittorent", so we create it here
        users.${service.user} =
          mkForce {
            inherit (service) group;
            isSystemUser = true;
          }
          // optionalAttrs (config.nixflix.globals.uids ? ${cfg.user}) {
            uid = mkForce config.nixflix.globals.uids.${cfg.user};
          };
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
        after = [ "nixflix-setup-dirs.service" ] ++ config.nixflix.serviceDependencies;
        requires = [ "nixflix-setup-dirs.service" ] ++ config.nixflix.serviceDependencies;
        serviceConfig.UMask = "0002";
        preStart = lib.mkIf (cfg.categories != { }) (lib.mkAfter syncCategories);
      };

    }
    (mkIf (config.nixflix.vpn.enable && cfg.vpn.enable) {
      systemd.services.qbittorrent.vpnConfinement = {
        enable = true;
        vpnNamespace = cfg.vpn.namespace;
      };
      vpnNamespaces.${cfg.vpn.namespace}.portMappings = [
        {
          from = service.webuiPort;
          to = service.webuiPort;
          protocol = "tcp";
        }
      ];
    })
  ]);
}

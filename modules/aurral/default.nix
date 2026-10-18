{ config, lib, ... }:
with lib;
let
  inherit (import ../../lib/mkVirtualHosts.nix { inherit lib config; }) mkVirtualHost;
  cfg = config.nixflix.aurral;
  hostname = "${cfg.subdomain}.${config.nixflix.reverseProxy.domain}";
in
{
  imports = [
    # ./setupService.nix
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

        downloadsDir = mkOption {
          type = types.path;
          default = "${config.nixflix.downloadsDir}";
          defaultText = literalExpression ''"''${nixflix.downloadsDir}"'';
          description = "Directory where completed downloads are stored.";
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
    {
      services.aurral =
        (builtins.removeAttrs cfg [
          "connectionAddress"
          "downloadsDir"
          "reverseProxy"
          "subdomain"
          "users"
          "vpn"
        ])
        // {
          environment = {
            DOWNLOAD_FOLDER = cfg.downloadsDir;
          };
        };

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
  ]);
}

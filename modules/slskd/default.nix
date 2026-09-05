{
  config,
  lib,
  ...
}:
with lib;
let
  inherit (import ../../lib/mkVirtualHosts.nix { inherit lib config; }) mkVirtualHost;
  secrets = import ../../lib/secrets { inherit lib; };
  cfg = config.nixflix.slskd;
  hostname = "${cfg.subdomain}.${config.nixflix.reverseProxy.domain}";

  environmentFile = "${cfg.dataDir}/environment";
in
{
  options.nixflix.slskd = mkOption {
    type = types.submodule {
      freeformType = types.attrsOf types.anything;
      options = {
        enable = mkEnableOption "slskd Soulseek client";

        user = mkOption {
          type = types.str;
          default = "slskd";
          description = "User under which slskd runs.";
        };

        group = mkOption {
          type = types.str;
          default = config.nixflix.globals.libraryOwner.group;
          defaultText = literalExpression "config.nixflix.globals.libraryOwner.group";
          description = "Group under which slskd runs.";
        };

        dataDir = mkOption {
          type = types.path;
          default = "${config.nixflix.stateDir}/slskd";
          defaultText = literalExpression ''"''${nixflix.stateDir}/slskd"'';
          description = "Directory holding slskd's generated credentials file. slskd's own application state lives under /var/lib/slskd (managed by the upstream systemd StateDirectory).";
        };

        downloadsDir = mkOption {
          type = types.path;
          default = "${config.nixflix.downloadsDir}/slskd";
          defaultText = literalExpression ''"''${nixflix.downloadsDir}/slskd"'';
          description = "Directory where completed Soulseek downloads are stored.";
        };

        incompleteDir = mkOption {
          type = types.path;
          default = "${config.nixflix.downloadsDir}/.incomplete-slskd";
          defaultText = literalExpression ''"''${nixflix.downloadsDir}/.incomplete-slskd"'';
          description = "Directory where in-progress Soulseek downloads are stored.";
        };

        username = secrets.mkSecretOption {
          nullable = true;
          default = null;
          description = "Soulseek network username. Required when `nixflix.slskd.enable = true`.";
        };

        password = secrets.mkSecretOption {
          nullable = true;
          default = null;
          description = "Soulseek network password. Required when `nixflix.slskd.enable = true`.";
        };

        apiKey = secrets.mkSecretOption {
          nullable = true;
          default = null;
          description = ''
            API key securing slskd's own REST API. Consumed by clients such as DroppedNeedle.

            Can be created with the following:

            ```bash
            openssl rand -hex 16
            ```
          '';
        };

        openFirewall = mkOption {
          type = types.bool;
          default = false;
          description = "Open the Soulseek peer listen port (`settings.soulseek.listen_port`) in the firewall.";
        };

        settings = mkOption {
          type = types.submodule {
            freeformType = types.attrsOf types.anything;
            options = {
              web.port = mkOption {
                type = types.port;
                default = 5030;
                description = "Port on which the slskd web UI/API listens.";
              };

              soulseek.listen_port = mkOption {
                type = types.port;
                default = 50300;
                description = "Port on which slskd listens for incoming Soulseek peer connections.";
              };

              shares.directories = mkOption {
                type = types.listOf types.path;
                default = [ ];
                example = [ "/data/media/music" ];
                description = "Directories shared with the Soulseek network.";
              };
            };
          };
          default = { };
          description = ''
            Extra/overriding [slskd settings](https://github.com/slskd/slskd/blob/master/docs/config.md),
            passed straight through to `services.slskd.settings` on top of the
            `directories` defaults derived from the options above (e.g. `downloadsDir`).
          '';
        };

        subdomain = mkOption {
          type = types.str;
          default = "slskd";
          description = "Subdomain prefix for reverse proxy routing.";
        };

        reverseProxy = {
          expose = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to expose the slskd web UI via the reverse proxy.";
          };
        };

        vpn = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Whether to route slskd traffic through the VPN.

              When `true`, slskd is confined to the WireGuard network namespace
              (requires `nixflix.vpn.enable = true`).
            '';
          };
        };

        connectionAddress = mkOption {
          type = types.str;
          readOnly = true;
          default =
            if config.nixflix.vpn.enable && cfg.vpn.enable then
              config.vpnNamespaces.wg.namespaceAddress
            else
              "127.0.0.1";
          description = "Address at which this service is reachable (derived).";
        };
      };
    };
    default = { };
    description = ''
      slskd Soulseek client configuration.

      Any option accepted by [`services.slskd`](https://search.nixos.org/options?channel=unstable&query=slskd&type=options)
      that isn't overridden above (e.g. `package`, `nginx`) can be set directly
      here too (e.g. `nixflix.slskd.package = ...;`) and is passed straight
      through.
    '';
  };

  config = mkIf (config.nixflix.enable && cfg.enable) (mkMerge [
    (mkVirtualHost {
      inherit hostname;
      inherit (cfg.reverseProxy) expose;
      port = cfg.settings.web.port;
      upstreamHost = cfg.connectionAddress;
    })
    {
      assertions = [
        {
          assertion = cfg.vpn.enable -> config.nixflix.vpn.enable;
          message = "nixflix.slskd.vpn.enable = true requires nixflix.vpn.enable = true.";
        }
        {
          assertion = cfg.username != null && cfg.password != null;
          message = "nixflix.slskd.enable = true requires nixflix.slskd.username and nixflix.slskd.password to be set.";
        }
      ];

      systemd.tmpfiles.settings."10-slskd" = {
        ${cfg.dataDir}.d = {
          mode = "0750";
          inherit (cfg) user group;
        };
        # Group-writable (not the usual 0750): nixflix.droppedneedle's user
        # reads/moves completed downloads from here too, via the same group.
        ${cfg.downloadsDir}.d = {
          mode = "0770";
          inherit (cfg) user group;
        };
        ${cfg.incompleteDir}.d = {
          mode = "0750";
          inherit (cfg) user group;
        };
      };

      systemd.services.slskd-secrets = {
        description = "Materialize slskd secrets";
        after = [ "nixflix-setup-dirs.service" ];
        requires = [ "nixflix-setup-dirs.service" ];
        before = [ "slskd.service" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = cfg.user;
          Group = cfg.group;
          UMask = "0077";
        };

        script = ''
          umask 077
          cat > ${environmentFile} <<EOF
          SLSKD_SLSK_USERNAME=${secrets.toShellValue cfg.username}
          SLSKD_SLSK_PASSWORD=${secrets.toShellValue cfg.password}
          ${optionalString (cfg.apiKey != null) "SLSKD_API_KEY=${secrets.toShellValue cfg.apiKey}"}
          EOF
        '';
      };

      services.slskd =
        (builtins.removeAttrs cfg [
          "dataDir"
          "downloadsDir"
          "incompleteDir"
          "username"
          "password"
          "apiKey"
          "settings"
          "subdomain"
          "reverseProxy"
          "vpn"
          "connectionAddress"
        ])
        // {
          domain = null;
          inherit environmentFile;
          settings = recursiveUpdate {
            directories = {
              downloads = cfg.downloadsDir;
              incomplete = cfg.incompleteDir;
            };
          } cfg.settings;
        };

      systemd.services.slskd = {
        after = [
          "nixflix-setup-dirs.service"
          "slskd-secrets.service"
        ]
        ++ config.nixflix.serviceDependencies;
        requires = [
          "nixflix-setup-dirs.service"
          "slskd-secrets.service"
        ]
        ++ config.nixflix.serviceDependencies;
      };
    }
    (mkIf (config.nixflix.vpn.enable && cfg.vpn.enable) {
      systemd.services.slskd.vpnConfinement = {
        enable = true;
        vpnNamespace = "wg";
      };
      vpnNamespaces.wg.portMappings = [
        {
          from = cfg.settings.soulseek.listen_port;
          to = cfg.settings.soulseek.listen_port;
          protocol = "tcp";
        }
        {
          from = cfg.settings.web.port;
          to = cfg.settings.web.port;
          protocol = "tcp";
        }
      ];
    })
  ]);
}

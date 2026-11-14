{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../../lib/mkVirtualHosts.nix { inherit lib config; }) mkVirtualHost;
  inherit (config.nixflix) globals;
  cfg = config.nixflix.pinchflat;

  hostname = "${cfg.subdomain}.${config.nixflix.reverseProxy.domain}";

  mediaDirRule = {
    inherit (globals.libraryOwner) user group;
    mode = "0775";
  };
in
{
  options.nixflix.pinchflat = lib.mkOption {
    type = lib.types.submodule {
      freeformType = lib.types.attrsOf lib.types.anything;
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Whether to enable Pinchflat, a self-hosted YouTube media manager.

            Uses all of the same options as [nixpkgs pinchflat](https://search.nixos.org/options?channel=unstable&query=services.pinchflat).

            Pinchflat always listens on all interfaces (`0.0.0.0`, or `::` with
            `extraConfig.ENABLE_IPV6`); it has no bind address setting. The web UI
            is kept off the network by the NixOS firewall, so leave `openFirewall`
            set to `false` and use the reverse proxy unless you want direct LAN access.
          '';
        };

        package = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          # `or null` so a nixpkgs without pinchflat-ngx reaches the assertion
          # below instead of throwing a missing-attribute error
          default = pkgs.pinchflat-ngx or null;
          defaultText = lib.literalExpression "pkgs.pinchflat-ngx";
          example = lib.literalExpression "pkgs.pinchflat-ngx";
          description = ''
            The pinchflat-ngx package to use.

            `pinchflat-ngx` is only in nixpkgs unstable, so on a stable channel
            set this to the package from nixpkgs unstable.
          '';
        };

        user = lib.mkOption {
          type = lib.types.str;
          default = "pinchflat";
          description = "User account under which Pinchflat runs.";
        };

        group = lib.mkOption {
          type = lib.types.str;
          default = globals.libraryOwner.group;
          defaultText = lib.literalExpression "config.nixflix.globals.libraryOwner.group";
          description = "Group under which Pinchflat runs.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 8945;
          description = "Port on which the Pinchflat web interface is available.";
        };

        mediaDir = lib.mkOption {
          type = lib.types.str;
          default = "${config.nixflix.mediaDir}/youtube";
          defaultText = lib.literalExpression ''"''${config.nixflix.mediaDir}/youtube"'';
          example = "/data/media/youtube";
          description = "Directory into which Pinchflat downloads videos.";
        };

        showsDir = lib.mkOption {
          type = lib.types.str;
          default = "${config.nixflix.pinchflat.mediaDir}/shows";
          defaultText = lib.literalExpression ''"''${config.nixflix.pinchflat.mediaDir}/shows"'';
          example = "/data/media/youtube";
          description = ''
            Folder that holds one subfolder per channel, which the Jellyfin
            `YouTube` library points at. The default matches the output path
            template of Pinchflat's "Media Center" media profile preset
            (`/shows/<channel>/...`), so that preset works unchanged. Set it to
            `nixflix.pinchflat.mediaDir` if your template has no `/shows` prefix.
          '';
        };

        selfhosted = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Use Pinchflat's built-in, publicly known {env}`SECRET_KEY_BASE`.
            Either this or `secretsFile` must be set. Only use this on a private network.
          '';
        };

        secretsFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          example = "/run/secrets/pinchflat";
          description = ''
            Environment file with secrets such as {env}`SECRET_KEY_BASE`
            (at least 64 bytes, e.g. from `openssl rand -hex 64`),
            {env}`BASIC_AUTH_USERNAME` and {env}`BASIC_AUTH_PASSWORD`.
            Either this or `selfhosted` must be set.
          '';
        };

        connectionAddress = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          default =
            if config.nixflix.vpn.enable && cfg.vpn.enable then
              config.vpnNamespaces.${cfg.vpn.namespace}.namespaceAddress
            else
              "127.0.0.1";
          description = "Address at which this service is reachable (derived).";
        };

        vpn = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Whether to route Pinchflat traffic through the VPN.

              When `false`, Pinchflat bypasses the VPN.
              When `true`, Pinchflat is confined to the WireGuard network namespace (requires nixflix.vpn.enable = true).
            '';
          };

          namespace = lib.mkOption {
            type = lib.types.str;
            default = config.nixflix.vpn.namespace;
            defaultText = lib.literalExpression "config.nixflix.vpn.namespace";
            description = "Name of the VPN network namespace to confine Pinchflat to when `vpn.enable = true`.";
          };
        };

        subdomain = lib.mkOption {
          type = lib.types.str;
          default = "pinchflat";
          description = "Subdomain prefix for reverse proxy.";
        };

        reverseProxy = {
          expose = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to expose Pinchflat via the reverse proxy.";
          };
        };
      };
    };
  };

  config = lib.mkIf (config.nixflix.enable && cfg.enable) (
    lib.mkMerge [
      (mkVirtualHost {
        inherit hostname;
        inherit (cfg.reverseProxy) expose;
        inherit (cfg) port;
        upstreamHost = cfg.connectionAddress;
        # The UI is Phoenix LiveView, which runs over a websocket
        websocketUpgrade = true;
      })
      {
        assertions = [
          {
            assertion = cfg.selfhosted || cfg.secretsFile != null;
            message = "Either nixflix.pinchflat.selfhosted must be true, or nixflix.pinchflat.secretsFile must be set.";
          }
          {
            assertion = cfg.package != null;
            message = "nixflix.pinchflat.package is null: pkgs.pinchflat-ngx does not exist in this nixpkgs (it is only in nixpkgs unstable). Set nixflix.pinchflat.package to pinchflat-ngx from nixpkgs unstable.";
          }
        ];

        services.pinchflat = builtins.removeAttrs cfg (
          [
            "connectionAddress"
            "reverseProxy"
            "showsDir"
            "subdomain"
            "vpn"
          ]
          ++ lib.optional (cfg.package == null) "package"
        );

        systemd = {
          services.pinchflat = {
            after = config.nixflix.serviceDependencies;
            requires = config.nixflix.serviceDependencies;
            serviceConfig = {
              SupplementaryGroups = [ globals.libraryOwner.group ];
              # yt-dlp output must stay group-writable so other media-group
              # services (e.g. Maintainerr) can delete or rename it
              UMask = "0002";
            };
          };

          # showsDir too, or jellyfin-libraries' `mkdir -p` would create it root-owned 0755.
          # Separate definitions so showsDir == mediaDir merges instead of a duplicate-attribute error
          tmpfiles.settings."10-pinchflat" = lib.mkMerge [
            { ${cfg.mediaDir}.d = mediaDirRule; }
            { ${cfg.showsDir}.d = mediaDirRule; }
          ];
        };

        users = {
          # nixpkgs' `services.pinchflat.[user|group]` only gets created
          # when the value is "pinchflat", so we create it here
          groups.${cfg.group} = { };

          users.${cfg.user} = {
            inherit (cfg) group;
            isSystemUser = true;
          }
          // lib.optionalAttrs (globals.uids ? ${cfg.user}) { uid = lib.mkForce globals.uids.${cfg.user}; };
        };
      }
      (lib.mkIf (config.nixflix.vpn.enable && cfg.vpn.enable) {
        systemd.services.pinchflat.vpnConfinement = {
          enable = true;
          vpnNamespace = cfg.vpn.namespace;
        };
        vpnNamespaces.${cfg.vpn.namespace}.portMappings = [
          {
            from = cfg.port;
            to = cfg.port;
            protocol = "tcp";
          }
        ];
      })
    ]
  );
}

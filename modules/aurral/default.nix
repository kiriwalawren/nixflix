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
  cfg = config.nixflix.aurral;
  hostname = "${cfg.subdomain}.${config.nixflix.reverseProxy.domain}";
in
{
  imports = [
    ./lidarr.nix
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

        downloadsDir = mkOption {
          type = types.path;
          default = "${config.nixflix.downloadsDir}/aurral";
          defaultText = literalExpression ''"''${nixflix.downloadsDir}/aurral"'';
          description = "Directory where completed downloads are stored.";
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
          "downloadsDir"
          "oidc"
          "publicUrl"
          "reverseProxy"
          "settings"
          "subdomain"
          "vpn"
        ])
        // {
          environment = {
            DOWNLOAD_FOLDER = cfg.downloadsDir;
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

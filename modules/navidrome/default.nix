{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../../lib/mkVirtualHosts.nix { inherit lib config; }) mkVirtualHost;
  cfg = config.nixflix.navidrome;

  secrets = import ../../lib/secrets { inherit lib; };

  hostname = "${cfg.subdomain}.${config.nixflix.reverseProxy.domain}";
in
{
  imports = [
    ./setupService.nix
    ./usersService.nix
  ];

  options.nixflix.navidrome = lib.mkOption {
    type = lib.types.submodule {
      freeformType = lib.types.attrsOf lib.types.anything;
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Whether to enable the Navidrome music server.

            Uses all of the same options as [nixpkgs navidrome](https://search.nixos.org/options?channel=unstable&query=navidrome).
          '';
        };

        user = lib.mkOption {
          type = lib.types.str;
          default = "navidrome";
          description = "User account under which navidrome runs.";
        };

        group = lib.mkOption {
          type = lib.types.str;
          default = config.nixflix.globals.libraryOwner.group;
          description = "Group under which navidrome runs.";
        };

        users = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                userName = lib.mkOption {
                  type = lib.types.str;
                  example = "username";
                  default = null;
                  description = "Username for the user.";
                };

                email = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  example = "test@example.com";
                  default = null;
                  description = "The user's email.";
                };

                mutable = lib.mkOption {
                  type = lib.types.bool;
                  example = false;
                  description = ''
                    Functions like mutableUsers in NixOS users.users."user"
                    If true, the first time the user is created, all configured options
                    are overwritten. Any modifications from the GUI will take priority,
                    and no nix configuration changes will have any effect.
                    If false however, all options are overwritten as specified in the nix configuration,
                    which means any change through the Navidrome GUI will have no effect after a rebuild.

                    Note: Passwords are only set during user creation and are never updated
                    declaratively, regardless of the mutable setting. To change a user's password,
                    use the Navidrome web interface.
                  '';
                  default = true;
                };

                isAdmin = lib.mkOption {
                  type = lib.types.bool;
                  example = true;
                  description = "Whether or not this user is an admin";
                  default = false;
                };

                password = secrets.mkSecretOption {
                  default = null;
                  description = "User's password.";
                };
              };
            }
          );
        };

        settings = lib.mkOption {
          type = lib.types.submodule {
            freeformType = (pkgs.formats.json { }).type;

            options = {
              Port = lib.mkOption {
                type = lib.types.port;
                default = 4533;
                description = "Port number to listen to.";
              };

              Address = lib.mkOption {
                type = lib.types.str;
                default =
                  if config.nixflix.vpn.enable && cfg.vpn.enable then
                    config.vpnNamespaces.wg.namespaceAddress
                  else if config.nixflix.reverseProxy.enable then
                    "127.0.0.1"
                  else
                    "0.0.0.0";
                description = "Bind address for the WebUI";
              };

              MusicFolder = lib.mkOption {
                type = lib.types.str;
                default = builtins.head config.nixflix.lidarr.mediaDirs;
                defaultText = lib.literalExpression "builtins.head config.nixflix.lidarr.mediaDirs";
                example = "/data/media/music";
                description = ''
                  Folder where your music library is stored. Can be read-only.
                  This becomes the default library when using multi-library setup.
                '';
              };

              DataFolder = lib.mkOption {
                type = lib.types.path;
                default = "${config.nixflix.stateDir}/navidrome";
                defaultText = lib.literalExpression ''"''${nixflix.stateDir}/navidrome"'';
                description = "Directory containing Navidrome data and configuration.";
              };

              CacheFolder = lib.mkOption {
                type = lib.types.path;
                default = "${config.nixflix.navidrome.settings.DataFolder}/cache";
                defaultText = lib.literalExpression ''"''${config.nixflix.navidrome.settings.DataFolder}/cache"'';
                description = "Directory containing Navidrome cache.";
              };

              BaseUrl = lib.mkOption {
                type = lib.types.str;
                default =
                  if config.nixflix.reverseProxy.enable then
                    "${config.nixflix.reverseProxy.httpScheme}://${hostname}"
                  else
                    "";
                example = "http://${hostname}:${toString cfg.settings.Port}";
                defaultText = lib.literalExpression ''
                  if cfg.reverseProxy.enable then
                    "''${config.nixflix.reverseProxy.httpScheme}://''${hostname}:''${cfg.settings.Port}"
                  else
                    "";
                '';
              };

              EnforceNonRootUser = lib.mkOption {
                type = lib.types.bool;
                default = true;
                example = false;
                description = ''
                  When enabled, Navidrome will exit with an error if it detects it’s running as root (UID 0).
                  This validation happens early, before any filesystem operations.
                '';
              };
            };
          };

          description = "Configuration for Navidrome, see [Navidrome configuration](https://www.navidrome.org/docs/usage/configuration-options/) for supported values.";
        };

        connectionAddress = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          default =
            if config.nixflix.vpn.enable && cfg.vpn.enable then
              config.vpnNamespaces.wg.namespaceAddress
            else if cfg.settings.Address == "*" || cfg.settings.Address == "0.0.0.0" then
              "127.0.0.1"
            else
              cfg.settings.Address;
          description = "Address at which this service is reachable (derived).";
        };

        vpn = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            defaultText = lib.literalExpression "config.nixflix.vpn.enable";
            description = ''
              Whether to route Navidrome traffic through the VPN.

              When `false`, Navidrome bypasses the VPN.
              When `true`, Navidrome is confined to the WireGuard network namespace (requires nixflix.vpn.enable = true).
            '';
          };
        };

        subdomain = lib.mkOption {
          type = lib.types.str;
          default = "navidrome";
          description = "Subdomain prefix for reverse proxy.";
        };

        reverseProxy = {
          expose = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to expose Navidrome via the reverse proxy.";
          };
        };
      };
    };
  };

  config = lib.mkIf (config.nixflix.enable && cfg != null && cfg.enable) (
    lib.mkMerge [
      (mkVirtualHost {
        inherit hostname;
        inherit (cfg.reverseProxy) expose;
        port = cfg.settings.Port;
        upstreamHost = cfg.connectionAddress;
      })
      {
        assertions = [
          {
            assertion = lib.any (user: user.isAdmin) (lib.attrValues cfg.users);
            message = "At least one Navidrome user must have isAdmin = true.";
          }
        ];
      }
      {
        services.navidrome = builtins.removeAttrs cfg [
          "connectionAddress"
          "reverseProxy"
          "subdomain"
          "users"
          "vpn"
        ];

        systemd = {
          tmpfiles.settings.navidromeDirs = {
            "${cfg.settings.DataFolder}"."d" = lib.mkForce {
              mode = "755";
              inherit (cfg) user group;
            };
            "${cfg.settings.CacheFolder}"."d" = lib.mkForce {
              mode = "755";
              inherit (cfg) user group;
            };
            "${cfg.settings.MusicFolder}"."d" = lib.mkForce {
              group = ":${cfg.group}";
            };
          };
        };

        users = {
          # nixpkgs' `service.navidrome.[user|group]` only gets created
          # when the value is "navidrome", so we create it here
          users.${cfg.user} =
            lib.mkForce {
              inherit (cfg) group;
              isSystemUser = true;
            }
            // lib.optionalAttrs (config.nixflix.globals.uids ? ${cfg.user}) {
              uid = lib.mkForce config.nixflix.globals.uids.${cfg.user};
            };

          groups.${cfg.group} = lib.mkForce { };
        };
      }
    ]
  );
}

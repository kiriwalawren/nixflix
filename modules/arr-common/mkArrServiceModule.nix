{
  config,
  lib,
  pkgs,
  ...
}: serviceName: extraConfigOptions:
with lib; let
  inherit (config) nixflix;
  inherit (nixflix) globals;
  cfg = config.nixflix.${serviceName};
  stateDir = "${nixflix.stateDir}/${serviceName}";

  arrConfigModule = import ./configModule.nix {inherit lib;};
  mkArrHostConfigService = import ./hostConfigService.nix {inherit lib pkgs;};
  mkArrRootFoldersService = import ./rootFoldersService.nix {inherit lib pkgs;};
  mkArrDownloadClientsService = import ./downloadClientsService.nix {inherit lib pkgs;};
  capitalizedName = toUpper (substring 0 1 serviceName) + substring 1 (-1) serviceName;
  usesMediaDirs = !(elem serviceName ["prowlarr"]);
  serviceSupportsUserGroup = !(elem serviceName ["prowlarr"]);
in {
  options.nixflix.${serviceName} =
    {
      enable = mkEnableOption "${capitalizedName}";

      vpn = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Whether to route ${capitalizedName} traffic through the VPN.
            When false (default), ${capitalizedName} bypasses the VPN to prevent Cloudflare and image provider blocks.
            When true, ${capitalizedName} routes through the VPN (requires nixflix.mullvad.enable = true).
          '';
        };
      };

      user = mkOption {
        type = types.str;
        default = serviceName;
        description = "User under which the service runs";
      };

      group = mkOption {
        type = types.str;
        default = serviceName;
        description = "Group under which the service runs";
      };

      config = mkOption {
        type =
          arrConfigModule
          (
            extraConfigOptions
            // {
              downloadClients = mkOption {
                type = types.listOf (types.submodule {
                  freeformType = types.attrsOf types.anything;
                  options = {
                    enable = mkOption {
                      type = types.bool;
                      default = true;
                      description = "Whether or not this download client is enabled.";
                    };
                    name = mkOption {
                      type = types.str;
                      description = "User-defined name for the download client instance";
                    };
                    implementationName = mkOption {
                      type = types.str;
                      description = "Type of download client to configure (matches schema implementationName)";
                      example = "SABnzbd";
                    };
                    apiKeyPath = mkOption {
                      type = types.str;
                      description = "Path to file containing the API key for the download client";
                    };
                  };
                });
                default = [];
                description = ''
                  List of download clients to configure via the API /downloadclient endpoint.
                  Any additional attributes beyond name, implementationName, and apiKeyPath
                  will be applied as field values to the download client schema.
                  The useSsl field defaults to true if not specified.
                '';
              };
            }
            // optionalAttrs usesMediaDirs {
              rootFolders = mkOption {
                type = types.listOf types.attrs;
                default = [];
                description = ''
                  List of root folders to create via the API /rootfolder endpoint.
                  Each folder is an attribute set that will be converted to JSON and sent to the API.

                  For Sonarr/Radarr, a simple path is sufficient: {path = "/path/to/folder";}
                  For Lidarr, additional fields are required like defaultQualityProfileId, etc.
                '';
              };
            }
          );
        default = {};
        description = "${capitalizedName} configuration options that will be set via the API.";
      };
    }
    // optionalAttrs usesMediaDirs {
      mediaDirs = mkOption {
        type = types.listOf (types.submodule {
          options = {
            dir = mkOption {
              type = types.str;
              description = "Directory path";
            };
            owner = mkOption {
              type = types.str;
              default = "root";
              description = "Directory owner";
            };
          };
        });
        default = [];
        description = "List of media directories to create and manage";
      };
    };

  config = mkIf (nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.vpn.enable -> config.nixflix.mullvad.enable;
        message = "Cannot enable VPN routing for ${capitalizedName} (nixflix.${serviceName}.vpn.enable = true) when Mullvad VPN is disabled. Please set nixflix.mullvad.enable = true.";
      }
    ];

    nixflix.${serviceName}.config = {
      apiKeyPath = mkDefault null;
      hostConfig = {
        username = mkDefault serviceName;
        passwordPath = mkDefault null;
        instanceName = mkDefault capitalizedName;
        urlBase = mkDefault (
          if nixflix.serviceNameIsUrlBase
          then "/${serviceName}"
          else ""
        );
      };
      downloadClients = mkDefault (
        optionals (config.nixflix.sabnzbd.enable or false) [
          {
            name = "SABnzbd";
            implementationName = "SABnzbd";
            inherit (config.nixflix.sabnzbd) apiKeyPath;
            urlBase = config.nixflix.sabnzbd.settings.url_base;
          }
        ]
      );
    };

    nixflix.dirRegistrations =
      [
        {
          inherit (cfg) group;
          dir = stateDir;
          owner = cfg.user;
        }
      ]
      ++ optionals usesMediaDirs (map (mediaDir: {
          inherit (cfg) group;
          inherit (mediaDir) dir owner;
        })
        cfg.mediaDirs);

    services = {
      ${serviceName} =
        {
          inherit (cfg) enable;
          dataDir = stateDir;
        }
        // optionalAttrs serviceSupportsUserGroup {
          inherit (cfg) user group;
        }
        // {
          settings =
            {
              auth = {
                required = "Enabled";
                method = "Forms";
              };
              server = {inherit (cfg.config.hostConfig) port urlBase;};
            }
            // optionalAttrs config.services.postgresql.enable {
              log.dbEnabled = true;
              postgres = {
                inherit (cfg) user;
                host = "/run/postgresql";
                port = 5432;
                mainDb = cfg.user;
                logDb = cfg.user;
              };
            };
        };

      postgresql = mkIf config.services.postgresql.enable {
        ensureDatabases = [cfg.user];
        ensureUsers = [
          {
            name = cfg.user;
            ensureDBOwnership = true;
          }
        ];
      };

      nginx = mkIf nixflix.nginx.enable {
        virtualHosts.localhost.locations."${
          if cfg.config.hostConfig.urlBase == ""
          then "/"
          else cfg.config.hostConfig.urlBase
        }" = {
          proxyPass = "http://127.0.0.1:${builtins.toString cfg.config.hostConfig.port}";
          recommendedProxySettings = true;
          extraConfig = ''
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Server $host;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_redirect off;
          '';
        };
      };
    };

    users = {
      groups.${cfg.group} = optionalAttrs (globals.gids ? ${cfg.group}) {
        gid = globals.gids.${cfg.group};
      };
      users.${cfg.user} =
        {
          inherit (cfg) group;
          isSystemUser = true;
        }
        // optionalAttrs (globals.uids ? ${cfg.user}) {
          uid = globals.uids.${cfg.user};
        };
    };

    systemd.services =
      {
        # Service that waits for PostgreSQL database role to be ready
        "${serviceName}-wait-for-db" = mkIf config.services.postgresql.enable {
          description = "Wait for ${capitalizedName} PostgreSQL database role to be ready";
          after = ["postgresql.service" "postgresql-setup.service"];
          before = ["postgresql-ready.target"];
          requiredBy = ["postgresql-ready.target"];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            TimeoutStartSec = "5min";
            User = cfg.user;
            Group = cfg.group;
          };

          script = ''
            while true; do
              if ${pkgs.postgresql}/bin/psql -h /run/postgresql -d ${cfg.user} -c "SELECT 1" > /dev/null 2>&1; then
                echo "${capitalizedName} PostgreSQL database is ready"
                exit 0
              fi
              echo "Waiting for PostgreSQL role ${capitalizedName}..."
              sleep 1
            done
          '';
        };

        # Ensure main service (radarr.service, etc.) starts after
        # directories are created and configured dependencies
        ${serviceName} = {
          after =
            ["nixflix-setup-dirs.service"]
            ++ (optional (cfg.config.apiKeyPath != null && cfg.config.hostConfig.passwordPath != null) "${serviceName}-env.service")
            ++ (optional config.services.postgresql.enable "postgresql-ready.target")
            ++ (optional config.nixflix.mullvad.enable "mullvad-config.service");
          requires =
            ["nixflix-setup-dirs.service"]
            ++ (optional (cfg.config.apiKeyPath != null && cfg.config.hostConfig.passwordPath != null) "${serviceName}-env.service")
            ++ (optional config.services.postgresql.enable "postgresql-ready.target");
          wants = optional config.nixflix.mullvad.enable "mullvad-config.service";

          # Always use static users and configure VPN bypass
          serviceConfig =
            {
              # DynamicUser causes issues with VPN bypass and permissions
              DynamicUser = mkForce false;
              User = cfg.user;
              Group = cfg.group;
            }
            // optionalAttrs (cfg.config.apiKeyPath != null && cfg.config.hostConfig.passwordPath != null) {
              EnvironmentFile = "/run/${serviceName}/env";
            }
            // optionalAttrs (config.nixflix.mullvad.enable && !cfg.vpn.enable) {
              # Bypass VPN by wrapping with mullvad-exclude
              ExecStart = mkForce (pkgs.writeShellScript "${serviceName}-vpn-bypass" ''
                exec /run/wrappers/bin/mullvad-exclude ${getExe config.services.${serviceName}.package} \
                  -nobrowser -data='${stateDir}'
              '');
              # mullvad-exclude needs CAP_SYS_ADMIN to manipulate cgroups
              AmbientCapabilities = "CAP_SYS_ADMIN";
              # Delegate allows the service to manage its cgroup subtree
              Delegate = mkForce true;
            };
        };
      }
      # Only create config and rootfolders services if apiKeyPath is configured
      // optionalAttrs (cfg.config.apiKeyPath != null && cfg.config.hostConfig.passwordPath != null) {
        # Create environment file setup service
        "${serviceName}-env" = {
          description = "Setup ${capitalizedName} environment file";
          wantedBy = ["${serviceName}.service"];
          before = ["${serviceName}.service"];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };

          script = let
            envVar = toUpper serviceName + "__AUTH__APIKEY";
          in ''
            mkdir -p /run/${serviceName}
            echo "${envVar}=$(cat ${cfg.config.apiKeyPath})" > /run/${serviceName}/env
            chown ${cfg.user}:${cfg.group} /run/${serviceName}/env
            chmod 0400 /run/${serviceName}/env
          '';
        };

        # Configure service via API
        "${serviceName}-config" = mkArrHostConfigService serviceName cfg.config;
      }
      # Only create root folders service if rootFolders is not empty
      // optionalAttrs (usesMediaDirs && cfg.config.apiKeyPath != null && cfg.config.rootFolders != []) {
        "${serviceName}-rootfolders" = mkArrRootFoldersService serviceName cfg.config;
      }
      # Only create download clients service if downloadClients is not empty
      // optionalAttrs (cfg.config.apiKeyPath != null) {
        "${serviceName}-downloadclients" = mkArrDownloadClientsService serviceName cfg.config;
      };
  };
}

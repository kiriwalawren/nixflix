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
  capitalizedName = toUpper (substring 0 1 serviceName) + substring 1 (-1) serviceName;
  usesDynamicUser = elem serviceName ["prowlarr"];
  usesMediaDirs = !(elem serviceName ["prowlarr"]);
  effectiveUser =
    if usesDynamicUser
    then serviceName
    else cfg.user;
in {
  options.nixflix.${serviceName} =
    {
      enable = mkEnableOption "${capitalizedName}";

      config = mkOption {
        type =
          arrConfigModule
          (extraConfigOptions
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
            });
        default = {};
        description = "${capitalizedName} configuration options that will be set via the API.";
      };
    }
    // optionalAttrs (!usesDynamicUser) {
      group = mkOption {
        type = types.str;
        default = serviceName;
        description = "Group under which the service runs";
      };

      user = mkOption {
        type = types.str;
        default = serviceName;
        description = "User under which the service runs";
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
    # Set pattern-based defaults
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
    };

    # Register directories to be created
    nixflix.dirRegistrations =
      [
        (
          if usesDynamicUser
          then {
            dir = stateDir;
            owner = "root";
            group = "root";
            mode = "0700";
          }
          else {
            inherit (cfg) group;
            dir = stateDir;
            owner = cfg.user;
          }
        )
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
                user = effectiveUser;
                host = "/run/postgresql";
                port = 5432;
                mainDb = effectiveUser;
                logDb = effectiveUser;
              };
            };
        }
        // optionalAttrs (!usesDynamicUser) {
          inherit (cfg) user group;
        };

      postgresql = mkIf config.services.postgresql.enable {
        ensureDatabases = [effectiveUser];
        ensureUsers = [
          {
            name = effectiveUser;
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

    users = mkIf (!usesDynamicUser) {
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

          serviceConfig =
            {
              Type = "oneshot";
              RemainAfterExit = true;
              TimeoutStartSec = "5min";
            }
            // optionalAttrs (!usesDynamicUser) {
              User = cfg.user;
              Group = cfg.group;
            };

          script = let
            dbUser = effectiveUser;
            psqlCmd =
              if usesDynamicUser
              then "${pkgs.sudo}/bin/sudo -u postgres ${pkgs.postgresql}/bin/psql"
              else "${pkgs.postgresql}/bin/psql -h /run/postgresql";
            checkCmd =
              if usesDynamicUser
              then "SELECT 1 FROM pg_database WHERE datname='${dbUser}'"
              else "SELECT 1";
          in ''
            while true; do
              if ${psqlCmd} -d ${dbUser} -c "${checkCmd}" > /dev/null 2>&1; then
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
            ++ (optional config.services.postgresql.enable "postgresql-ready.target")
            ++ (optional config.nixflix.mullvad.enable "mullvad-config.service");
          requires =
            ["nixflix-setup-dirs.service"]
            ++ (optional config.services.postgresql.enable "postgresql-ready.target");
          wants = optional config.nixflix.mullvad.enable "mullvad-config.service";
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
            ${optionalString (!usesDynamicUser) "chown ${cfg.user}:${cfg.group} /run/${serviceName}/env"}
            chmod 0${
              if usesDynamicUser
              then "444"
              else "400"
            } /run/${serviceName}/env
          '';
        };

        ${serviceName} = {
          after =
            ["${serviceName}-env.service" "nixflix-setup-dirs.service"]
            ++ (optional config.services.postgresql.enable "postgresql-ready.target")
            ++ (optional config.nixflix.mullvad.enable "mullvad-config.service");
          requires =
            ["${serviceName}-env.service" "nixflix-setup-dirs.service"]
            ++ (optional config.services.postgresql.enable "postgresql-ready.target");
          wants = optional config.nixflix.mullvad.enable "mullvad-config.service";
          serviceConfig.EnvironmentFile = "/run/${serviceName}/env";
        };

        # Configure service via API
        "${serviceName}-config" = mkArrHostConfigService serviceName cfg.config;
      }
      # Only create root folders service if rootFolders is not empty
      // optionalAttrs (usesMediaDirs && cfg.config.apiKeyPath != null && cfg.config.rootFolders != []) {
        "${serviceName}-rootfolders" = mkArrRootFoldersService serviceName cfg.config;
      };
  };
}

serviceName: extraConfigOptions: {
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  arrConfigModule = import ./configModule.nix extraConfigOptions {inherit lib;};
  mkArrHostConfigService = import ./hostConfigService.nix {inherit lib pkgs;};
  mkArrRootFoldersService = import ./rootFoldersService.nix {inherit lib pkgs;};
  capitalizedName = toUpper (substring 0 1 serviceName) + substring 1 (-1) serviceName;
in {
  options.nixflix.${serviceName} = {
    enable = mkEnableOption "${capitalizedName}";

    usesDynamicUser = mkOption {
      type = types.bool;
      default = false;
      description = "Whether the service uses systemd DynamicUser";
    };

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

    config = mkOption {
      type = arrConfigModule;
      default = {};
      description = "${capitalizedName} configuration options that will be set via the API.";
    };
  };

  config = let
    inherit (config) nixflix;
    inherit (nixflix) globals;
    cfg = config.nixflix.${serviceName};
    stateDir = "${nixflix.stateDir}/${serviceName}";
  in
    mkIf (nixflix.enable && cfg.enable) {
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
            if cfg.usesDynamicUser
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
        ++ (map (mediaDir: {
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
                postgres = {
                  inherit (cfg) user;
                  host = "/run/postgresql";
                  port = 5432;
                  mainDb = cfg.user;
                  logDb = cfg.user;
                };
              };
          }
          // optionalAttrs (!cfg.usesDynamicUser) {
            inherit (cfg) user group;
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

      users = mkIf (!cfg.usesDynamicUser) {
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
            wantedBy = ["postgresql-ready.target"];

            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              User = cfg.user;
              Group = cfg.group;
              TimeoutStartSec = "5min";
            };

            script = ''
              while true; do
                if ${pkgs.postgresql}/bin/psql -h /run/postgresql -d ${cfg.user} -c "SELECT 1;" > /dev/null 2>&1; then
                  echo "${capitalizedName} PostgreSQL database is ready"
                  exit 0
                fi
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
              ${optionalString (!cfg.usesDynamicUser) "chown ${cfg.user}:${cfg.group} /run/${serviceName}/env"}
              chmod 0${
                if cfg.usesDynamicUser
                then "444"
                else "400"
              } /run/${serviceName}/env
            '';
          };

          ${serviceName} = {
            after = ["${serviceName}-env.service"];
            requires = ["${serviceName}-env.service"];
            serviceConfig.EnvironmentFile = "/run/${serviceName}/env";
          };

          # Configure service via API
          "${serviceName}-config" = mkArrHostConfigService serviceName cfg.config;
        }
        # Only create root folders service if rootFolders is not empty
        // optionalAttrs (cfg.config.apiKeyPath != null && cfg.config.rootFolders != []) {
          "${serviceName}-rootfolders" = mkArrRootFoldersService serviceName cfg.config;
        };
    };
}

{
  config,
  lib,
  pkgs,
  ...
}: serviceName: extraConfigOptions:
with lib; let
  inherit (config) nixflix;
  inherit (nixflix) globals;
  cfg = nixflix.${serviceName};
  stateDir = "${nixflix.stateDir}/${serviceName}";

  mkWaitForApiScript = import ./mkWaitForApiScript.nix {inherit lib pkgs;};
  hostConfig = import ./hostConfig.nix {inherit lib pkgs serviceName;};
  rootFolders = import ./rootFolders.nix {inherit lib pkgs serviceName;};
  downloadClients = import ./downloadClients.nix {inherit lib pkgs serviceName;};
  delayProfiles = import ./delayProfiles.nix {inherit lib pkgs serviceName;};
  capitalizedName = toUpper (substring 0 1 serviceName) + substring 1 (-1) serviceName;
  screamingName = toUpper serviceName;
  usesMediaDirs = !(elem serviceName ["prowlarr"]);

  mkServarrSettingsOptions = _name:
    lib.mkOption {
      type = lib.types.submodule {
        freeformType = (pkgs.formats.ini {}).type;
        options = {
          update = {
            mechanism = lib.mkOption {
              type = with lib.types;
                nullOr (enum [
                  "external"
                  "builtIn"
                  "script"
                ]);
              description = "which update mechanism to use";
              default = "external";
            };
            automatically = lib.mkOption {
              type = lib.types.bool;
              description = "Automatically download and install updates.";
              default = false;
            };
          };
          server = {
            port = lib.mkOption {
              type = lib.types.port;
              description = "Port Number";
            };
          };
          log = {
            analyticsEnabled = lib.mkOption {
              type = lib.types.bool;
              description = "Send Anonymous Usage Data";
              default = false;
            };
          };
        };
      };
      defaultText = lib.literalExpression ''
        {
          auth = {
            required = "Enabled";
            method = "Forms";
          };
          server = {
            inherit (nixflix.${serviceName}.config.hostConfig) port urlBase;
          };
        } // lib.optionalAttrs config.services.postgresql.enable {
          log.dbEnabled = true;
          postgres = {
            user = nixflix.${serviceName}.user;
            host = "/run/postgresql";
            port = 5432;
            mainDb = nixflix.${serviceName}.user;
            logDb = nixflix.${serviceName}.user;
          };
        }
      '';
      example = lib.options.literalExpression ''
        {
          update.mechanism = "internal";
          server = {
            urlbase = "localhost";
            port = ${toString port};
            bindaddress = "*";
          };
        }
      '';
      default = {};
      description = ''
        Attribute set of arbitrary config options.
        Please consult the documentation at the [wiki](https://wiki.servarr.com/useful-tools#using-environment-variables-for-config).

        WARNING: this configuration is stored in the world-readable Nix store!
        Don't put secrets here!
      '';
    };

  mkServarrSettingsEnvVars = name: settings:
    lib.pipe settings [
      (lib.mapAttrsRecursive (
        path: value:
          lib.optionalAttrs (value != null) {
            name = lib.toUpper "${name}__${lib.concatStringsSep "__" path}";
            value = toString (
              if lib.isBool value
              then lib.boolToString value
              else value
            );
          }
      ))
      (lib.collect (x: lib.isString x.name or false && lib.isString x.value or false))
      lib.listToAttrs
    ];
in {
  options.nixflix.${serviceName} =
    {
      enable = mkEnableOption "${capitalizedName}";
      package = lib.mkPackageOption pkgs serviceName {};

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

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Open ports in the firewall for the Radarr web interface.";
      };

      settings = mkServarrSettingsOptions serviceName;

      config = mkOption {
        type = types.submodule {
          options =
            {
              apiVersion = mkOption {
                type = types.str;
                default = "v3";
                description = "Current version of the API of the service";
              };

              apiKeyPath = mkOption {
                type = types.nullOr types.path;
                default = null;
                description = "Path to API key secret file";
              };
            }
            // extraConfigOptions
            // {
              downloadClients = downloadClients.options;
              hostConfig = hostConfig.options;
            }
            // optionalAttrs usesMediaDirs {
              rootFolders = rootFolders.options;
              delayProfiles = delayProfiles.options;
            };
        };
        default = {};
        description = "${capitalizedName} configuration options that will be set via the API.";
      };
    }
    // optionalAttrs usesMediaDirs {
      mediaDirs = mkOption {
        type = types.listOf types.path;
        default = [];
        defaultText = literalExpression ''[nixflix.mediaDir + "/<media-type>"]'';
        description = "List of media directories to create and manage";
      };
    };

  config = mkIf (nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.vpn.enable -> nixflix.mullvad.enable;
        message = "Cannot enable VPN routing for ${capitalizedName} (nixflix.${serviceName}.vpn.enable = true) when Mullvad VPN is disabled. Please set nixflix.mullvad.enable = true.";
      }
    ];

    nixflix.${serviceName} = {
      settings = mkDefault ({
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
        });
      config = {
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
          optionals (nixflix.sabnzbd.enable or false) [
            {
              name = "SABnzbd";
              implementationName = "SABnzbd";
              inherit (nixflix.sabnzbd) apiKeyPath;
              inherit (nixflix.sabnzbd.settings) host;
              inherit (nixflix.sabnzbd.settings) port;
              urlBase = nixflix.sabnzbd.settings.url_base;
            }
          ]
        );
      };
    };

    services = {
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
          home = stateDir;
          isSystemUser = true;
        }
        // optionalAttrs (globals.uids ? ${cfg.user}) {
          uid = globals.uids.${cfg.user};
        };
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [cfg.config.hostConfig.port];
    };

    systemd.tmpfiles = {
      settings."10-${serviceName}".${stateDir}.d = {
        inherit (cfg) user group;
        mode = "0700";
      };

      rules =
        optionals usesMediaDirs (map (mediaDir: "d '${mediaDir}' 0770 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -")
          cfg.mediaDirs);
    };

    systemd.services =
      {
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

        ${serviceName} = {
          description = capitalizedName;
          environment = mkServarrSettingsEnvVars screamingName cfg.settings;

          after =
            ["network.target"]
            ++ (optional (cfg.config.apiKeyPath != null && cfg.config.hostConfig.passwordPath != null) "${serviceName}-env.service")
            ++ (optional config.services.postgresql.enable "postgresql-ready.target")
            ++ (optional nixflix.mullvad.enable "mullvad-config.service");
          requires =
            (optional (cfg.config.apiKeyPath != null && cfg.config.hostConfig.passwordPath != null) "${serviceName}-env.service")
            ++ (optional config.services.postgresql.enable "postgresql-ready.target");
          wants = optional nixflix.mullvad.enable "mullvad-config.service";
          wantedBy = ["multi-user.target"];

          serviceConfig =
            {
              Type = "simple";
              User = cfg.user;
              Group = cfg.group;
              ExecStart = "${getExe cfg.package} -nobrowser -data='${stateDir}'";
              ExecStartPost = mkWaitForApiScript serviceName cfg.config;
              Restart = "on-failure";
            }
            // optionalAttrs (cfg.config.apiKeyPath != null && cfg.config.hostConfig.passwordPath != null) {
              EnvironmentFile = "/run/${serviceName}/env";
            }
            // optionalAttrs (nixflix.mullvad.enable && !cfg.vpn.enable) {
              ExecStart = mkForce (pkgs.writeShellScript "${serviceName}-vpn-bypass" ''
                exec /run/wrappers/bin/mullvad-exclude ${getExe cfg.package} \
                  -nobrowser -data='${stateDir}'
              '');
              AmbientCapabilities = "CAP_SYS_ADMIN";
              Delegate = mkForce true;
            };
        };
      }
      // optionalAttrs (cfg.config.apiKeyPath != null && cfg.config.hostConfig.passwordPath != null) {
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

        "${serviceName}-config" = hostConfig.mkService cfg.config;
      }
      // optionalAttrs (usesMediaDirs && cfg.config.apiKeyPath != null && cfg.config.rootFolders != []) {
        "${serviceName}-rootfolders" = rootFolders.mkService cfg.config;
      }
      // optionalAttrs (usesMediaDirs && cfg.config.apiKeyPath != null) {
        "${serviceName}-delayprofiles" = delayProfiles.mkService cfg.config;
      }
      // optionalAttrs (cfg.config.apiKeyPath != null) {
        "${serviceName}-downloadclients" = downloadClients.mkService cfg.config;
      };
  };
}

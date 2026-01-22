{
  config,
  lib,
  pkgs,
  ...
}: serviceName: extraConfigOptions:
with lib; let
  secrets = import ../lib/secrets {inherit lib;};
  inherit (config) nixflix;
  inherit (nixflix) globals;
  cfg = nixflix.${serviceName};
  stateDir = "${nixflix.stateDir}/${serviceName}";

  mkWaitForApiScript = import ./mkWaitForApiScript.nix {inherit lib pkgs;};
  hostConfig = import ./hostConfig.nix {inherit lib pkgs serviceName;};
  rootFolders = import ./rootFolders.nix {inherit lib pkgs serviceName;};
  downloadClients = import ./downloadClients.nix {inherit lib pkgs serviceName config;};
  delayProfiles = import ./delayProfiles.nix {inherit lib pkgs serviceName;};
  capitalizedName = toUpper (substring 0 1 serviceName) + substring 1 (-1) serviceName;
  usesMediaDirs = !(elem serviceName ["prowlarr"]);

  serviceBase = builtins.elemAt (splitString "-" serviceName) 0;

  mkServarrSettingsEnvVars = name: settings:
    pipe settings [
      (mapAttrsRecursive (
        path: value:
          optionalAttrs (value != null) {
            name = toUpper "${name}__${concatStringsSep "__" path}";
            value = toString (
              if isBool value
              then boolToString value
              else value
            );
          }
      ))
      (collect (x: isString x.name or false && isString x.value or false))
      listToAttrs
    ];
in {
  options.nixflix.${serviceName} =
    {
      enable = mkEnableOption "${capitalizedName}";
      package = mkPackageOption pkgs serviceBase {};

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

      openFirewall = mkOption {
        type = types.bool;
        default = false;
        description = "Open ports in the firewall for the Radarr web interface.";
      };

      settings = mkOption {
        type = types.submodule {
          freeformType = (pkgs.formats.ini {}).type;
          options = {
            app = {
              instanceName = mkOption {
                type = types.str;
                description = "Name of the instance";
                default = capitalizedName;
              };
            };
            update = {
              mechanism = mkOption {
                type = with types;
                  nullOr (enum [
                    "external"
                    "builtIn"
                    "script"
                  ]);
                description = "which update mechanism to use";
                default = "external";
              };
              automatically = mkOption {
                type = types.bool;
                description = "Automatically download and install updates.";
                default = false;
              };
            };
            server = {
              port = mkOption {
                type = types.port;
                description = "Port Number";
              };
            };
            log = {
              analyticsEnabled = mkOption {
                type = types.bool;
                description = "Send Anonymous Usage Data";
                default = false;
              };
            };
          };
        };
        defaultText = literalExpression ''
          {
            auth = {
              required = "Enabled";
              method = "Forms";
            };
            server = {
              inherit (nixflix.${serviceName}.config.hostConfig) port urlBase;
            };
          } // optionalAttrs config.services.postgresql.enable {
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
        example = options.literalExpression ''
          {
            update.mechanism = "internal";
            server = {
              urlbase = "localhost";
              port = 8989;
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

      config = mkOption {
        type = types.submodule {
          options =
            {
              apiVersion = mkOption {
                type = types.str;
                default = "v3";
                description = "Current version of the API of the service";
              };

              apiKey = secrets.mkSecretOption {
                default = null;
                description = "API key for ${capitalizedName}.";
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
        apiKey = mkDefault null;
        hostConfig = {
          username = mkDefault serviceBase;
          password = mkDefault null;
          instanceName = mkDefault capitalizedName;
          urlBase = mkDefault (
            if nixflix.nginx.enable
            then "/${serviceName}"
            else ""
          );
        };
        downloadClients = mkDefault (
          optionals (nixflix.sabnzbd.enable or false) [
            ({
                name = "SABnzbd";
                implementationName = "SABnzbd";
                apiKey = nixflix.sabnzbd.settings.misc.api_key;
                inherit (nixflix.sabnzbd.settings.misc) host;
                inherit (nixflix.sabnzbd.settings.misc) port;
                urlBase = nixflix.sabnzbd.settings.misc.url_base;
              }
              // optionalAttrs (serviceName == "radarr") {
                movieCategory = serviceName;
              }
              // optionalAttrs (elem serviceName ["sonarr" "sonarr-anime"]) {
                tvCategory = serviceName;
              }
              // optionalAttrs (serviceName == "lidarr") {
                musicCategory = serviceName;
              }
              // optionalAttrs (serviceName == "prowlarr") {
                category = serviceName;
              })
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
        }" = let
          themeParkUrl = "https://theme-park.dev/css/base/${serviceName}/${nixflix.theme.name}.css";
        in {
          proxyPass = "http://127.0.0.1:${builtins.toString cfg.config.hostConfig.port}";
          recommendedProxySettings = true;
          extraConfig = ''
            proxy_redirect off;

            ${
              if nixflix.theme.enable
              then ''
                proxy_set_header Accept-Encoding "";
                sub_filter '</body>' '<link rel="stylesheet" type="text/css" href="${themeParkUrl}"></body>';
                sub_filter_once on;
              ''
              else ""
            }
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

    networking.firewall = mkIf cfg.openFirewall {
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
          environment = mkServarrSettingsEnvVars (toUpper serviceBase) cfg.settings;

          after =
            ["network.target"]
            ++ (optional (cfg.config.apiKey != null && cfg.config.hostConfig.password != null) "${serviceName}-env.service")
            ++ (optional config.services.postgresql.enable "postgresql-ready.target")
            ++ (optional nixflix.mullvad.enable "mullvad-config.service");
          requires =
            (optional (cfg.config.apiKey != null && cfg.config.hostConfig.password != null) "${serviceName}-env.service")
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
            // optionalAttrs (cfg.config.apiKey != null && cfg.config.hostConfig.password != null) {
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
      // optionalAttrs (cfg.config.apiKey != null && cfg.config.hostConfig.password != null) {
        "${serviceName}-env" = {
          description = "Setup ${capitalizedName} environment file";
          wantedBy = ["${serviceName}.service"];
          before = ["${serviceName}.service"];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };

          script = let
            envVar = toUpper serviceBase + "__AUTH__APIKEY";
          in ''
            mkdir -p /run/${serviceName}
            ${secrets.toShellValue envVar cfg.config.apiKey}
            echo "${envVar}=''${${envVar}}" > /run/${serviceName}/env
            chown ${cfg.user}:${cfg.group} /run/${serviceName}/env
            chmod 0400 /run/${serviceName}/env
          '';
        };

        "${serviceName}-config" = hostConfig.mkService cfg.config;
      }
      // optionalAttrs (usesMediaDirs && cfg.config.apiKey != null && cfg.config.rootFolders != []) {
        "${serviceName}-rootfolders" = rootFolders.mkService cfg.config;
      }
      // optionalAttrs (usesMediaDirs && cfg.config.apiKey != null) {
        "${serviceName}-delayprofiles" = delayProfiles.mkService cfg.config;
      }
      // optionalAttrs (cfg.config.apiKey != null) {
        "${serviceName}-downloadclients" = downloadClients.mkService cfg.config;
      };
  };
}

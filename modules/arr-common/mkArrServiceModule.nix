{
  config,
  lib,
  pkgs,
  ...
}:
serviceName: extraConfigOptions:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  inherit (config.nixflix) globals;
  cfg = config.nixflix.${serviceName};
  stateDir = "${config.nixflix.stateDir}/${serviceName}";

  mkWaitForApiScript = import ./mkWaitForApiScript.nix { inherit lib pkgs; };
  hostConfig = import ./hostConfig.nix { inherit lib pkgs serviceName; };
  rootFolders = import ./rootFolders.nix { inherit lib pkgs serviceName; };
  delayProfiles = import ./delayProfiles.nix { inherit lib pkgs serviceName; };
  capitalizedName = toUpper (substring 0 1 serviceName) + substring 1 (-1) serviceName;
  usesMediaDirs = !(elem serviceName [ "prowlarr" ]);
  hostname = "${cfg.subdomain}.${config.nixflix.nginx.domain}";

  serviceBase = builtins.elemAt (splitString "-" serviceName) 0;

  mkServarrSettingsEnvVars =
    name: settings:
    pipe settings [
      (mapAttrsRecursive (
        path: value:
        optionalAttrs (value != null) {
          name = toUpper "${name}__${concatStringsSep "__" path}";
          value = toString (if isBool value then boolToString value else value);
        }
      ))
      (collect (x: isString x.name or false && isString x.value or false))
      listToAttrs
    ];
in
{
  options.nixflix.${serviceName} = {
    enable = mkEnableOption "${capitalizedName}";
    package = mkPackageOption pkgs serviceBase { };

    vpn = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to route ${capitalizedName} traffic through the VPN.
          When false (default), ${capitalizedName} bypasses the VPN to prevent Cloudflare and image provider blocks.
          When true, ${capitalizedName} routes through the VPN (requires `nixflix.mullvad.enable = true`).
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

    subdomain = mkOption {
      type = types.str;
      default = serviceName;
      description = "Subdomain prefix for nginx reverse proxy. Service accessible at `<subdomain>.<domain>`.";
    };

    settings = mkOption {
      type = types.submodule {
        freeformType = (pkgs.formats.ini { }).type;
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
              type =
                with types;
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
            inherit (config.nixflix.${serviceName}.config.hostConfig) port urlBase;
          };
        } // optionalAttrs config.services.postgresql.enable {
          log.dbEnabled = true;
          postgres = {
            user = config.nixflix.${serviceName}.user;
            host = "/run/postgresql";
            port = config.services.postgresql.settings.port;
            mainDb = config.nixflix.${serviceName}.user;
            logDb = "''${config.nixflix.${serviceName}.user}-logs";
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
      default = { };
      description = ''
        Attribute set of arbitrary config options.
        Please consult the documentation at the [wiki](https://wiki.servarr.com/useful-tools#using-environment-variables-for-config).

        !!! warning

            This configuration is stored in the world-readable Nix store!
            Don't put secrets here!
      '';
    };

    config = mkOption {
      type = types.submodule {
        options = {
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
          hostConfig = hostConfig.options;
        }
        // optionalAttrs usesMediaDirs {
          rootFolders = rootFolders.options;
          delayProfiles = delayProfiles.options;
        };
      };
      default = { };
      description = "${capitalizedName} configuration options that will be set via the API.";
    };
  }
  // optionalAttrs usesMediaDirs {
    mediaDirs = mkOption {
      type = types.listOf types.path;
      default = [ ];
      defaultText = literalExpression ''[config.nixflix.mediaDir + "/<media-type>"]'';
      description = "List of media directories to create and manage";
    };
  };

  config = mkIf (config.nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.vpn.enable -> config.nixflix.mullvad.enable;
        message = "Cannot enable VPN routing for ${capitalizedName} (config.nixflix.${serviceName}.vpn.enable = true) when Mullvad VPN is disabled. Please set nixflix.mullvad.enable = true.";
      }
    ];

    nixflix.${serviceName} = {
      settings = {
        auth = {
          required = "Enabled";
          method = "Forms";
        };
        server = { inherit (cfg.config.hostConfig) port urlBase; };
      }
      // optionalAttrs config.services.postgresql.enable {
        log.dbEnabled = true;
        postgres = {
          inherit (cfg) user;
          inherit (config.services.postgresql.settings) port;
          host = "/run/postgresql";
          mainDb = cfg.user;
          logDb = "${cfg.user}-logs";
        };
      };
      config = {
        apiKey = mkDefault null;
        hostConfig = {
          username = mkDefault serviceBase;
          password = mkDefault null;
          instanceName = mkDefault capitalizedName;
        };
      };
    };

    services = {
      postgresql = mkIf config.services.postgresql.enable {
        ensureDatabases = [
          cfg.settings.postgres.mainDb
          cfg.settings.postgres.logDb
        ];
        ensureUsers = [
          {
            name = cfg.user;
          }
        ];
      };

      nginx.virtualHosts."${hostname}" = mkIf config.nixflix.nginx.enable {
        locations."/" =
          let
            themeParkUrl = "https://theme-park.dev/css/base/${serviceBase}/${config.nixflix.theme.name}.css";
          in
          {
            proxyPass = "http://127.0.0.1:${builtins.toString cfg.config.hostConfig.port}";
            recommendedProxySettings = true;
            extraConfig = ''
              proxy_redirect off;

              ${
                if config.nixflix.theme.enable then
                  ''
                    proxy_set_header Accept-Encoding "";
                    sub_filter '</body>' '<link rel="stylesheet" type="text/css" href="${themeParkUrl}"></body>';
                    sub_filter_once on;
                  ''
                else
                  ""
              }
            '';
          };
      };
    };

    networking.hosts = mkIf (config.nixflix.nginx.enable && config.nixflix.nginx.addHostsEntries) {
      "127.0.0.1" = [ hostname ];
    };

    users = {
      groups.${cfg.group} = optionalAttrs (globals.gids ? ${cfg.group}) {
        gid = globals.gids.${cfg.group};
      };
      users.${cfg.user} = {
        inherit (cfg) group;
        home = stateDir;
        isSystemUser = true;
      }
      // optionalAttrs (globals.uids ? ${cfg.user}) {
        uid = globals.uids.${cfg.user};
      };
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.config.hostConfig.port ];
    };

    systemd.tmpfiles.settings."10-${serviceName}" = {
      "${stateDir}".d = {
        inherit (cfg) user group;
        mode = "0755";
      };
    }
    // optionalAttrs usesMediaDirs (
      lib.mergeAttrsList (
        map (mediaDir: {
          "${mediaDir}".d = {
            inherit (globals.libraryOwner) user group;
            mode = "0775";
          };
        }) cfg.mediaDirs
      )
    );

    systemd.services = {
      "${serviceName}-setup-logs-db" = mkIf config.services.postgresql.enable {
        description = "Grant ownership of ${capitalizedName} databases";
        after = [
          "postgresql.service"
          "postgresql-setup.service"
        ];
        requires = [
          "postgresql.service"
          "postgresql-setup.service"
        ];
        before = [ "postgresql-ready.target" ];
        requiredBy = [ "postgresql-ready.target" ];

        serviceConfig = {
          User = "postgres";
          Group = "postgres";
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          ${pkgs.postgresql}/bin/psql  -tAc 'ALTER DATABASE "${cfg.settings.postgres.mainDb}" OWNER TO "${cfg.user}";'
          ${pkgs.postgresql}/bin/psql  -tAc 'ALTER DATABASE "${cfg.settings.postgres.logDb}" OWNER TO "${cfg.user}";'
        '';
      };

      "${serviceName}-wait-for-db" = mkIf config.services.postgresql.enable {
        description = "Wait for ${capitalizedName} PostgreSQL databases to be ready";
        after = [
          "postgresql.service"
          "postgresql-setup.service"
        ];
        before = [ "postgresql-ready.target" ];
        requiredBy = [ "postgresql-ready.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "5min";
          User = cfg.user;
          Group = cfg.group;
        };

        script = ''
          while true; do
            if ${pkgs.postgresql}/bin/psql -h /run/postgresql -d ${cfg.user} -c "SELECT 1" > /dev/null 2>&1 && \
               ${pkgs.postgresql}/bin/psql -h /run/postgresql -d ${cfg.user}-logs -c "SELECT 1" > /dev/null 2>&1; then
              echo "${capitalizedName} PostgreSQL databases are ready"
              exit 0
            fi
            echo "Waiting for ${capitalizedName} PostgreSQL databases..."
            sleep 1
          done
        '';
      };

      ${serviceName} = {
        description = capitalizedName;
        environment = mkServarrSettingsEnvVars (toUpper serviceBase) cfg.settings;

        after = [
          "network.target"
          "nixflix-setup-dirs.service"
        ]
        ++ (optional (
          cfg.config.apiKey != null && cfg.config.hostConfig.password != null
        ) "${serviceName}-env.service")
        ++ (optional config.services.postgresql.enable "postgresql-ready.target")
        ++ (optional config.nixflix.mullvad.enable "mullvad-config.service");
        requires = [
          "nixflix-setup-dirs.service"
        ]
        ++ (optional (
          cfg.config.apiKey != null && cfg.config.hostConfig.password != null
        ) "${serviceName}-env.service")
        ++ (optional config.services.postgresql.enable "postgresql-ready.target");
        wants = optional config.nixflix.mullvad.enable "mullvad-config.service";
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          ExecStart = "${getExe cfg.package} -nobrowser -data='${stateDir}'";
          ExecStartPost = "+" + (mkWaitForApiScript serviceName cfg.config);
          Restart = "on-failure";
        }
        // optionalAttrs (cfg.config.apiKey != null && cfg.config.hostConfig.password != null) {
          EnvironmentFile = "/run/${serviceName}/env";
        }
        // optionalAttrs (config.nixflix.mullvad.enable && !cfg.vpn.enable) {
          ExecStart = mkForce (
            pkgs.writeShellScript "${serviceName}-vpn-bypass" ''
              exec /run/wrappers/bin/mullvad-exclude ${getExe cfg.package} \
                -nobrowser -data='${stateDir}'
            ''
          );
          AmbientCapabilities = "CAP_SYS_ADMIN";
          Delegate = mkForce true;
        };
      };
    }
    // optionalAttrs (cfg.config.apiKey != null && cfg.config.hostConfig.password != null) {
      "${serviceName}-env" = {
        description = "Setup ${capitalizedName} environment file";
        wantedBy = [ "${serviceName}.service" ];
        before = [ "${serviceName}.service" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          mkdir -p /run/${serviceName}
          echo "${
            toUpper serviceBase + "__AUTH__APIKEY"
          }=${secrets.toShellValue cfg.config.apiKey}" > /run/${serviceName}/env
          chown ${cfg.user}:${cfg.group} /run/${serviceName}/env
          chmod 0400 /run/${serviceName}/env
        '';
      };

      "${serviceName}-config" = hostConfig.mkService cfg.config;
    }
    // optionalAttrs (usesMediaDirs && cfg.config.apiKey != null && cfg.config.rootFolders != [ ]) {
      "${serviceName}-rootfolders" = rootFolders.mkService cfg.config;
    }
    // optionalAttrs (usesMediaDirs && cfg.config.apiKey != null) {
      "${serviceName}-delayprofiles" = delayProfiles.mkService cfg.config;
    };
  };
}

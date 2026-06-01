{ serviceName }:
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix.${serviceName};
  secrets = import ../../lib/secrets { inherit lib; };
  inherit (import ./utils.nix { inherit lib pkgs serviceName; })
    capitalizedName
    serviceBase
    mkSecureCurl
    mkWaitForApiScript
    ;
in
{
  options.nixflix.${serviceName}.config.hostConfig = mkOption {
    type = types.submodule {
      options = {
        bindAddress = mkOption {
          type = types.str;
          default =
            if config.nixflix.vpn.enable && cfg.vpn.enable then
              config.vpnNamespaces.wg.namespaceAddress
            else if config.nixflix.reverseProxy.enable then
              "127.0.0.1"
            else
              "0.0.0.0";
          description = "Address to bind to";
        };

        port = mkOption {
          type = types.port;
          description = "Port the service listens on";
        };

        sslPort = mkOption {
          type = types.port;
          default = 9898;
          description = "SSL port";
        };

        enableSsl = mkOption {
          type = types.bool;
          default = false;
          description = "Enable SSL";
        };

        authenticationMethod = mkOption {
          type = types.enum [
            "none"
            "basic"
            "forms"
            "external"
          ];
          default = "forms";
          description = "Authentication method";
        };

        authenticationRequired = mkOption {
          type = types.enum [
            "enabled"
            "disabled"
            "disabledForLocalAddresses"
          ];
          default = "enabled";
          description = "Authentication requirement level";
        };

        username = secrets.mkSecretOption {
          nullable = true;
          default = serviceBase;
          description = "Username for web interface authentication.";
        };

        password = secrets.mkSecretOption {
          nullable = true;
          default = null;
          description = "Password for web interface authentication.";
        };

        urlBase = mkOption {
          type = types.str;
          default = "";
          example = "/takeMeThere";
          description = "URL base path";
        };

        applicationUrl = mkOption {
          type = types.str;
          default = "";
          description = "Application URL";
        };

        instanceName = mkOption {
          type = types.str;
          default = capitalizedName;
          description = "Instance name";
        };

        logLevel = mkOption {
          type = types.enum [
            "info"
            "debug"
            "trace"
          ];
          default = "info";
          description = "Log level";
        };

        logSizeLimit = mkOption {
          type = types.int;
          default = 1;
          description = "Log size limit in MB";
        };

        consoleLogLevel = mkOption {
          type = types.str;
          default = "";
          description = "Console log level";
        };

        branch = mkOption {
          type = types.str;
          description = "Update branch";
        };

        updateAutomatically = mkOption {
          type = types.bool;
          default = false;
          description = "Update automatically";
        };

        updateMechanism = mkOption {
          type = types.enum [
            "builtIn"
            "script"
            "external"
            "docker"
          ];
          default = "builtIn";
          description = "Update mechanism";
        };

        updateScriptPath = mkOption {
          type = types.str;
          default = "";
          description = "Update script path";
        };

        proxyEnabled = mkOption {
          type = types.bool;
          default = false;
          description = "Enable proxy";
        };

        proxyType = mkOption {
          type = types.enum [
            "http"
            "socks4"
            "socks5"
          ];
          default = "http";
          description = "Proxy type";
        };

        proxyHostname = mkOption {
          type = types.str;
          default = "";
          description = "Proxy hostname";
        };

        proxyPort = mkOption {
          type = types.port;
          default = 8080;
          description = "Proxy port";
        };

        proxyUsername = secrets.mkSecretOption {
          default = "";
          description = "Proxy username";
        };

        proxyPassword = secrets.mkSecretOption {
          default = "";
          description = "Proxy password";
        };

        proxyBypassFilter = mkOption {
          type = types.str;
          default = "";
          description = "Proxy bypass filter";
        };

        proxyBypassLocalAddresses = mkOption {
          type = types.bool;
          default = true;
          description = "Proxy bypass local addresses";
        };

        sslCertPath = mkOption {
          type = types.str;
          default = "";
          description = "SSL certificate path";
        };

        sslCertPassword = secrets.mkSecretOption {
          default = "";
          description = "SSL certificate password";
        };

        certificateValidation = mkOption {
          type = types.enum [
            "enabled"
            "disabled"
            "disabledForLocalAddresses"
          ];
          default = "enabled";
          description = "Certificate validation";
        };

        backupFolder = mkOption {
          type = types.str;
          default = "Backups";
          description = "Backup folder name";
        };

        backupInterval = mkOption {
          type = types.int;
          default = 7;
          description = "Backup interval in days";
        };

        backupRetention = mkOption {
          type = types.int;
          default = 28;
          description = "Backup retention in days";
        };

        launchBrowser = mkOption {
          type = types.bool;
          default = false;
          description = "Launch browser on start (not applicable for NixOS services)";
        };

        analyticsEnabled = mkOption {
          type = types.bool;
          default = false;
          description = "Enable analytics";
        };

        trustCgnatIpAddresses = mkOption {
          type = types.bool;
          default = false;
          description = "Trust CGNAT IP addresses";
        };
      };
    };
    default = { };
    description = "Host configuration options that will be set via the API /config/host endpoint";
  };

  config = mkMerge [
    (mkIf (config.nixflix.enable && cfg.enable) {
      assertions = [
        {
          assertion = (cfg.config.hostConfig.username == null) == (cfg.config.hostConfig.password == null);
          message = "nixflix.${serviceName}.config.hostConfig: username and password must both be set or both be null";
        }
      ];
    })

    (mkIf
      (
        config.nixflix.enable
        && cfg.enable
        && cfg.config.apiKey != null
        && cfg.config.hostConfig.password != null
      )
      {
        systemd.services."${serviceName}-config" =
          let
            hc = cfg.config.hostConfig;
            jqSecrets = secrets.mkJqSecretArgs {
              inherit (cfg.config) apiKey;
              inherit (hc)
                username
                password
                sslCertPassword
                proxyUsername
                proxyPassword
                ;
            };
          in
          {
            description = "Configure ${serviceName} via API";
            after = [ "${serviceName}.service" ];
            # DO NOT ADD `requires` here — <service>-config restarts
            # the service and would enter failed state as a result
            wantedBy = [ "multi-user.target" ];

            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStartPre = mkWaitForApiScript serviceName cfg.config;
              ExecStartPost = mkWaitForApiScript serviceName cfg.config;
            };

            script = ''
              set -eu

              BASE_URL="http://${hc.bindAddress}:${builtins.toString hc.port}${hc.urlBase}/api/${cfg.config.apiVersion}"

              echo "Fetching current host configuration..."
              HOST_CONFIG=$(${
                mkSecureCurl cfg.config.apiKey {
                  url = "$BASE_URL/config/host";
                  extraArgs = "-f";
                }
              } 2>/dev/null)

              if [ -z "$HOST_CONFIG" ]; then
                echo "Failed to fetch host configuration"
                exit 1
              fi

              CONFIG_ID=$(echo "$HOST_CONFIG" | ${pkgs.jq}/bin/jq -r '.id')

              echo "Building configuration..."
              NEW_CONFIG=$(${pkgs.jq}/bin/jq -n \
                ${jqSecrets.flagsString} \
                --argjson id "$CONFIG_ID" \
                --arg bindAddress ${escapeShellArg hc.bindAddress} \
                --arg authenticationMethod ${escapeShellArg hc.authenticationMethod} \
                --arg authenticationRequired ${escapeShellArg hc.authenticationRequired} \
                --arg logLevel ${escapeShellArg hc.logLevel} \
                --arg consoleLogLevel ${escapeShellArg hc.consoleLogLevel} \
                --arg branch ${escapeShellArg hc.branch} \
                --arg sslCertPath ${escapeShellArg hc.sslCertPath} \
                --arg urlBase ${escapeShellArg hc.urlBase} \
                --arg instanceName ${escapeShellArg hc.instanceName} \
                --arg applicationUrl ${escapeShellArg hc.applicationUrl} \
                --arg updateMechanism ${escapeShellArg hc.updateMechanism} \
                --arg updateScriptPath ${escapeShellArg hc.updateScriptPath} \
                --arg proxyType ${escapeShellArg hc.proxyType} \
                --arg proxyHostname ${escapeShellArg hc.proxyHostname} \
                --arg proxyBypassFilter ${escapeShellArg hc.proxyBypassFilter} \
                --arg certificateValidation ${escapeShellArg hc.certificateValidation} \
                --arg backupFolder ${escapeShellArg hc.backupFolder} \
                '{
                  id: $id,
                  bindAddress: $bindAddress,
                  port: ${builtins.toString hc.port},
                  sslPort: ${builtins.toString hc.sslPort},
                  enableSsl: ${boolToString hc.enableSsl},
                  launchBrowser: ${boolToString hc.launchBrowser},
                  authenticationMethod: $authenticationMethod,
                  authenticationRequired: $authenticationRequired,
                  analyticsEnabled: ${boolToString hc.analyticsEnabled},
                  username: ${jqSecrets.refs.username},
                  password: ${jqSecrets.refs.password},
                  passwordConfirmation: ${jqSecrets.refs.password},
                  logLevel: $logLevel,
                  logSizeLimit: ${builtins.toString hc.logSizeLimit},
                  consoleLogLevel: $consoleLogLevel,
                  branch: $branch,
                  apiKey: ${jqSecrets.refs.apiKey},
                  sslCertPath: $sslCertPath,
                  sslCertPassword: ${jqSecrets.refs.sslCertPassword},
                  urlBase: $urlBase,
                  instanceName: $instanceName,
                  applicationUrl: $applicationUrl,
                  updateAutomatically: ${boolToString hc.updateAutomatically},
                  updateMechanism: $updateMechanism,
                  updateScriptPath: $updateScriptPath,
                  proxyEnabled: ${boolToString hc.proxyEnabled},
                  proxyType: $proxyType,
                  proxyHostname: $proxyHostname,
                  proxyPort: ${builtins.toString hc.proxyPort},
                  proxyUsername: ${jqSecrets.refs.proxyUsername},
                  proxyPassword: ${jqSecrets.refs.proxyPassword},
                  proxyBypassFilter: $proxyBypassFilter,
                  proxyBypassLocalAddresses: ${boolToString hc.proxyBypassLocalAddresses},
                  certificateValidation: $certificateValidation,
                  backupFolder: $backupFolder,
                  backupInterval: ${builtins.toString hc.backupInterval},
                  backupRetention: ${builtins.toString hc.backupRetention},
                  trustCgnatIpAddresses: ${boolToString hc.trustCgnatIpAddresses}
                }')

              echo "Updating ${capitalizedName} configuration via API..."
              ${
                mkSecureCurl cfg.config.apiKey {
                  url = "$BASE_URL/config/host/$CONFIG_ID";
                  method = "PUT";
                  headers = {
                    "Content-Type" = "application/json";
                  };
                  data = "$NEW_CONFIG";
                  extraArgs = "-f";
                }
              } > /dev/null

              echo "Configuration updated successfully"

              echo "Restarting ${serviceName} service..."
              systemctl restart ${serviceName}.service
              echo "${capitalizedName} service restarted"
            '';
          };
      }
    )
  ];
}

{lib}:
with lib;
  types.submodule {
    options = {
      # Connection settings
      bindAddress = mkOption {
        type = types.str;
        default = "*";
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

      # Authentication settings
      authenticationMethod = mkOption {
        type = types.enum ["none" "basic" "forms" "external"];
        default = "forms";
        description = "Authentication method";
      };

      authenticationRequired = mkOption {
        type = types.enum ["enabled" "disabled" "disabledForLocalAddresses"];
        default = "enabled";
        description = "Authentication requirement level";
      };

      username = mkOption {
        type = types.str;
        default = null;
        description = "Username";
      };

      passwordPath = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to password secret file";
      };

      # URL settings
      urlBase = mkOption {
        type = types.str;
        default = "";
        description = "URL base path";
      };

      applicationUrl = mkOption {
        type = types.str;
        default = "";
        description = "Application URL";
      };

      instanceName = mkOption {
        type = types.str;
        description = "Instance name";
      };

      # Logging settings
      logLevel = mkOption {
        type = types.enum ["info" "debug" "trace"];
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

      # Update settings
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
        type = types.enum ["builtIn" "script" "external" "docker"];
        default = "builtIn";
        description = "Update mechanism";
      };

      updateScriptPath = mkOption {
        type = types.str;
        default = "";
        description = "Update script path";
      };

      # Proxy settings
      proxyEnabled = mkOption {
        type = types.bool;
        default = false;
        description = "Enable proxy";
      };

      proxyType = mkOption {
        type = types.enum ["http" "socks4" "socks5"];
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

      proxyUsername = mkOption {
        type = types.str;
        default = "";
        description = "Proxy username";
      };

      proxyPassword = mkOption {
        type = types.str;
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

      # SSL settings
      sslCertPath = mkOption {
        type = types.str;
        default = "";
        description = "SSL certificate path";
      };

      sslCertPassword = mkOption {
        type = types.str;
        default = "";
        description = "SSL certificate password";
      };

      certificateValidation = mkOption {
        type = types.enum ["enabled" "disabled" "disabledForLocalAddresses"];
        default = "enabled";
        description = "Certificate validation";
      };

      # Backup settings
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

      # Other settings
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
  }

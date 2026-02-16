{ lib }:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
in
types.submodule {
  options = {
    bindAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
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

    username = mkOption {
      type = types.str;
      default = null;
      description = "Username";
    };

    password = secrets.mkSecretOption {
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
}

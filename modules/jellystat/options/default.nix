{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  secrets = import ../../../lib/secrets { inherit lib; };
in
{
  options.nixflix.jellystat = {
    enable = mkEnableOption "Jellystat statistics for Jellyfin";

    package = mkPackageOption pkgs "jellystat" { };

    timezone = mkOption {
      type = types.str;
      default = if config.time.timeZone == null then "UTC" else config.time.timeZone;
      defaultText = literalExpression ''if config.time.timeZone == null then "UTC" else config.time.timeZone'';
      description = "Timezone for jellystat.";
    };

    jellyfin = {
      hostname = mkOption {
        type = types.str;
        default = config.nixflix.jellyfin.connectionAddress;
        defaultText = literalExpression "config.nixflix.jellyfin.connectionAddress";
        description = "Jellyfin server hostname or IP";
      };

      port = mkOption {
        type = types.port;
        default = config.nixflix.jellyfin.network.internalHttpPort or 8096;
        defaultText = literalExpression "config.nixflix.jellyfin.network.internalHttpPort";
        description = "Jellyfin server port";
      };

      useSsl = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to use SSL/HTTPS for Jellyfin connection";
      };

      urlBase = mkOption {
        type = types.str;
        default = config.nixflix.jellyfin.network.baseUrl or "";
        defaultText = literalExpression ''config.nixflix.jellyfin.network.baseUrl or ""'';
        description = "Jellyfin URL base path (e.g., /jellyfin)";
      };

      apiKey = secrets.mkSecretOption {
        default = config.nixflix.jellyfin.apiKey;
        defaultText = literalExpression "config.nixflix.jellyfin.apiKey";
        description = "Jellyfin API key for Jellystat.";
      };

      masterOverrideUser = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Master override user (in case username/password for setup is forgotten).";
      };

      masterOverridePassword = secrets.mkSecretOption {
        default = null;
        description = "Master override password.";
      };
    };

    jwtSecret = secrets.mkSecretOption {
      nullable = true;
      default = null;
      description = "JWT secret for session encryption. If not set, a random one will be generated.";
    };

    user = mkOption {
      type = types.str;
      default = "jellystat";
      description = "User under which the service runs.";
    };

    group = mkOption {
      type = types.str;
      default = "jellystat";
      description = "Group under which the service runs.";
    };

    dataDir = mkOption {
      type = types.path;
      default = "${config.nixflix.stateDir}/jellystat";
      defaultText = literalExpression ''"''${nixflix.stateDir}/jellystat"'';
      description = "Directory containing jellystat data and configuration.";
    };

    backupDir = mkOption {
      type = types.path;
      default = "${config.nixflix.stateDir}/jellystat/backups";
      defaultText = literalExpression ''"''${nixflix.stateDir}/jellystat/backups"'';
      description = "Directory for Jellystat backup data.";
    };

    port = mkOption {
      type = types.port;
      default = 2842;
      description = "Port on which jellystat listens.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open port in firewall for jellystat.";
    };

    subdomain = mkOption {
      type = types.str;
      default = "jellystat";
      description = "Subdomain prefix for reverse proxy.";
    };

    reverseProxy = {
      expose = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to expose Jellystat via the reverse proxy.";
      };
    };

    vpn = {
      enable = mkOption {
        type = types.bool;
        default = false;
        defaultText = literalExpression "config.nixflix.vpn.enable";
        description = ''
          Whether to route Jellystat traffic through the VPN.

          When `false`, Jellystat bypasses the VPN.
          When `true`, Jellystat is confined to the WireGuard network namespace (requires nixflix.vpn.enable = true).
        '';
      };
    };

    connectionAddress = mkOption {
      type = types.str;
      readOnly = true;
      default =
        if config.nixflix.vpn.enable && config.nixflix.jellystat.vpn.enable then
          config.vpnNamespaces.wg.namespaceAddress
        else
          "127.0.0.1";
      defaultText = literalExpression ''
        if config.nixflix.vpn.enable && config.nixflix.jellystat.vpn.enable
        then config.vpnNamespaces.wg.namespaceAddress
        else "127.0.0.1"
      '';
      description = "Address for connecting to this service.";
    };

    useWebsockets = mkOption {
      type = types.bool;
      default = true;
      description = "Use Jellyfin websockets for real-time session data";
    };

    watchSessionThreshold = mkOption {
      type = types.ints.positive;
      default = 1;
      description = "Minimum watch session duration in hours to include in statistics";
    };

    geoLocation = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable IP geolocation using MaxMind GeoLite";
      };

      accountId = mkOption {
        type = types.str;
        default = "";
        description = "MaxMind GeoLite account ID";
      };

      licenseKey = secrets.mkSecretOption {
        default = null;
        description = "MaxMind GeoLite license key";
      };
    };

    isEmby = mkOption {
      type = types.bool;
      default = false;
      description = "Use Emby API instead of Jellyfin";
    };
  };

  config.assertions = [
    {
      assertion = config.nixflix.jellystat.vpn.enable -> config.nixflix.vpn.enable;
      message = "Cannot enable VPN routing for Jellystat (nixflix.jellystat.vpn.enable = true) when VPN is not enabled. Please set nixflix.vpn.enable = true.";
    }
  ];
}

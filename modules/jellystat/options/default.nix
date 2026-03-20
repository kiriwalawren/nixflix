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

    jellyfin = {
      hostname = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Jellyfin server hostname or IP";
      };

      port = mkOption {
        type = types.port;
        default = 8096;
        description = "Jellyfin server port";
      };

      useSsl = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to use SSL/HTTPS for Jellyfin connection";
      };

      urlBase = mkOption {
        type = types.str;
        default = "";
        description = "Jellyfin URL base path (e.g., /jellyfin)";
      };

      apiKey = secrets.mkSecretOption {
        default = null;
        description = "Jellyfin API key. If nixflix.jellyfin is enabled, this is auto-detected.";
      };
    };

    database = {
      name = mkOption {
        type = types.str;
        default = "jellystat";
        description = "PostgreSQL database name for Jellystat";
      };
    };

    jwtSecret = secrets.mkSecretOption {
      default = null;
      description = "JWT secret for session encryption. If not set, a random one will be generated.";
    };

    user = mkOption {
      type = types.str;
      default = "jellystat";
      description = "User under which the service runs";
    };

    group = mkOption {
      type = types.str;
      default = "jellystat";
      description = "Group under which the service runs";
    };

    dataDir = mkOption {
      type = types.path;
      default = "${config.nixflix.stateDir}/jellystat";
      defaultText = literalExpression ''"''${nixflix.stateDir}/jellystat"'';
      description = "Directory containing jellystat data and configuration";
    };

    backupDir = mkOption {
      type = types.path;
      default = "${config.nixflix.stateDir}/jellystat/backups";
      defaultText = literalExpression ''"''${nixflix.stateDir}/jellystat/backups"'';
      description = "Directory for Jellystat backup data";
    };

    port = mkOption {
      type = types.port;
      default = 3000;
      description = "Port on which jellystat listens";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open port in firewall for jellystat";
    };

    subdomain = mkOption {
      type = types.str;
      default = "jellystat";
      description = "Subdomain prefix for nginx reverse proxy.";
    };

    vpn = {
      enable = mkOption {
        type = types.bool;
        default = config.nixflix.mullvad.enable;
        defaultText = literalExpression "config.nixflix.mullvad.enable";
        description = ''
          Whether to route Jellystat traffic through the VPN.
          When true (default), Jellystat routes through the VPN (requires nixflix.mullvad.enable = true).
          When false, Jellystat bypasses the VPN.
        '';
      };
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
}

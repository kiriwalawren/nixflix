{
  lib,
  config,
  ...
}:
with lib;
let
  secrets = import ../../../lib/secrets { inherit lib; };
in
{
  options.nixflix.jellyfin.network = {
    autoDiscovery = mkOption {
      type = types.bool;
      default = true;
      description = "Enable auto-discovery";
    };

    baseUrl = mkOption {
      type = types.str;
      default = if config.nixflix.nginx.enable then "jellyfin" else "";
      defaultText = literalExpression ''if config.nixflix.nginx.enable then "jellyfin" else ""'';
      description = "Base URL for Jellyfin (URL prefix) http://localhost:8096/<baseUrl>";
    };

    certificatePassword = secrets.mkSecretOption {
      default = "";
      description = "Certificate password.";
    };

    certificatePath = mkOption {
      type = types.oneOf [
        types.str
        types.path
      ];
      default = "";
      description = "Path to certificate file";
    };

    enableHttps = mkOption {
      type = types.bool;
      default = false;
      description = "Enable HTTPS";
    };

    enableIPv4 = mkOption {
      type = types.bool;
      default = true;
      description = "Enable IPv4";
    };

    enableIPv6 = mkOption {
      type = types.bool;
      default = false;
      description = "Enable IPv6";
    };

    enablePublishedServerUriByRequest = mkOption {
      type = types.bool;
      default = false;
      description = "Enable published server URI by request";
    };

    enableRemoteAccess = mkOption {
      type = types.bool;
      default = true;
      description = "Enable remote access. (Disabling this can cause unexpected authentication failures)";
    };

    enableUPnP = mkOption {
      type = types.bool;
      default = false;
      description = "Enable UPnP";
    };

    ignoreVirtualInterfaces = mkOption {
      type = types.bool;
      default = true;
      description = "Ignore virtual interfaces";
    };

    internalHttpPort = mkOption {
      type = types.ints.between 0 65535;
      default = 8096;
      description = "Internal HTTP port";
    };

    internalHttpsPort = mkOption {
      type = types.ints.between 0 65535;
      default = 8920;
      description = "Internal HTTPS port";
    };

    isRemoteIPFilterBlacklist = mkOption {
      type = types.bool;
      default = false;
      description = "Is remote IP filter a blacklist";
    };

    knownProxies = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of known proxies";
    };

    localNetworkAddresses = mkOption {
      type = types.bool;
      default = false;
      description = "Local network addresses";
    };

    localNetworkSubnets = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of local network subnets";
    };

    publicHttpPort = mkOption {
      type = types.ints.between 0 65535;
      default = 8096;
      description = "Public HTTP port";
    };

    publicHttpsPort = mkOption {
      type = types.ints.between 0 65535;
      default = 8920;
      description = "Public HTTPS port";
    };

    publishedServerUriBySubnet = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of published server URIs by subnet";
    };

    remoteIpFilter = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Remote IP filter list";
    };

    requireHttps = mkOption {
      type = types.bool;
      default = false;
      description = "Require HTTPS";
    };

    virtualInterfaceNames = mkOption {
      type = types.listOf types.str;
      default = [ "veth" ];
      description = "List of virtual interface names";
    };
  };
}

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
  imports = [
    ./jellyfin.nix
    ./radarr.nix
    ./sonarr.nix
    ./users.nix
  ];

  options.nixflix.seerr = {
    enable = mkEnableOption "Seerr media request manager";

    package = mkPackageOption pkgs "seerr" { };

    apiKey = secrets.mkSecretOption {
      description = "API key for Seerr.";
    };

    externalUrlScheme = mkOption {
      type = types.str;
      default = "http";
      example = "https";
      description = ''
        Scheme to use for external linking to other services
        from within Seerr.
      '';
    };

    user = mkOption {
      type = types.str;
      default = "seerr";
      description = "User under which the service runs";
    };

    group = mkOption {
      type = types.str;
      default = "seerr";
      description = "Group under which the service runs";
    };

    dataDir = mkOption {
      type = types.path;
      default = "${config.nixflix.stateDir}/seerr";
      defaultText = literalExpression ''"''${nixflix.stateDir}/seerr"'';
      description = "Directory containing Seerr data and configuration";
    };

    port = mkOption {
      type = types.port;
      default = 5055;
      description = "Port on which Seerr listens";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open port in firewall for Seerr";
    };

    subdomain = mkOption {
      type = types.str;
      default = "seerr";
      description = "Subdomain prefix for nginx reverse proxy.";
    };

    vpn = {
      enable = mkOption {
        type = types.bool;
        default = false;
        defaultText = literalExpression "config.nixflix.vpn.enable";
        description = ''
          Whether to route Seerr traffic through the VPN.

          When `false`, Seerr bypasses the VPN.
          When `true`, Seerr is confined to the WireGuard network namespace (requires nixflix.vpn.enable = true).
        '';
      };
    };
  };

  config.assertions = [
    {
      assertion = config.nixflix.seerr.vpn.enable -> config.nixflix.vpn.enable;
      message = "Cannot enable VPN routing for Seerr (nixflix.seerr.vpn.enable = true) when VPN is not enabled. Please set nixflix.vpn.enable = true.";
    }
  ];
}

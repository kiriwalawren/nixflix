{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  secrets = import ../../lib/secrets {inherit lib;};
in {
  imports = [
    ./jellyfin.nix
    ./radarr.nix
    ./sonarr.nix
    ./users.nix
  ];

  options.nixflix.seerr = {
    enable = mkEnableOption "Seerr media request manager";

    package = mkPackageOption pkgs "jellyseerr" {};

    apiKey = secrets.mkSecretOption {
      default = null;
      description = "API key for Seerr.";
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

    vpn = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to route Seerr traffic through the VPN.
          When true (default), Seerr routes through the VPN (requires nixflix.mullvad.enable = true).
          When false, Seerr bypasses the VPN.
        '';
      };
    };
  };
}

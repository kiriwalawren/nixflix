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

  options.nixflix.jellyseerr = {
    enable = mkEnableOption "Jellyseerr media request manager";

    package = mkPackageOption pkgs "jellyseerr" {};

    apiKey = secrets.mkSecretOption {
      default = null;
      description = "API key for Jellyseerr.";
    };

    user = mkOption {
      type = types.str;
      default = "jellyseerr";
      description = "User under which the service runs";
    };

    group = mkOption {
      type = types.str;
      default = "jellyseerr";
      description = "Group under which the service runs";
    };

    dataDir = mkOption {
      type = types.path;
      default = "${config.nixflix.stateDir}/jellyseerr";
      defaultText = literalExpression ''"''${nixflix.stateDir}/jellyseerr"'';
      description = "Directory containing jellyseerr data and configuration";
    };

    port = mkOption {
      type = types.port;
      default = 5055;
      description = "Port on which jellyseerr listens";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open port in firewall for jellyseerr";
    };

    vpn = {
      enable = mkOption {
        type = types.bool;
        default = config.nixflix.mullvad.enable;
        defaultText = literalExpression "config.nixflix.mullvad.enable";
        description = ''
          Whether to route Jellyseerr traffic through the VPN.
          When true (default), Jellyseerr routes through the VPN (requires nixflix.mullvad.enable = true).
          When false, Jellyseerr bypasses the VPN.
        '';
      };
    };
  };
}

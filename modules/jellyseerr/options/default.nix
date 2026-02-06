{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  secrets = import ../../lib/secrets {inherit lib;};

  jellyseerrWithBasePath = pkgs.jellyseerr.overrideAttrs (oldAttrs: {
    postPatch =
      (oldAttrs.postPatch or "")
      + ''
        echo "Patching next.config.js with basePath: ${config.nixflix.jellyseerr.basePath}"

        ${pkgs.gnused}/bin/sed -i \
          '/^module\.exports = {$/a\  basePath: "${config.nixflix.jellyseerr.basePath}",\n  assetPrefix: "${config.nixflix.jellyseerr.basePath}",' \
          next.config.js

        echo "Patched next.config.js:"
        cat next.config.js
      '';
  });
in {
  imports = [
    ./jellyfin.nix
    ./radarr.nix
    ./sonarr.nix
    ./users.nix
  ];

  options.nixflix.jellyseerr = {
    enable = mkEnableOption "Jellyseerr media request manager";

    package = mkOption {
      type = types.package;
      default =
        if config.nixflix.jellyseerr.basePath == ""
        then pkgs.jellyseerr
        else jellyseerrWithBasePath;
      defaultText = literalExpression ''
        if config.nixflix.jellyseerr.basePath == ""
        then pkgs.jellyseerr
        else jellyseerrWithBasePath;
      '';
      description = "Jellyseerr package (automatically patched when basePath is set)";
    };

    basePath = mkOption {
      type = types.str;
      default =
        if config.nixflix.nginx.enable
        then "/jellyseerr"
        else "";
      defaultText = literalExpression ''if config.nixflix.nginx.enable then "/jellyseerr" else ""'';
      description = ''
        Base path for Jellyseerr (URL prefix), e.g., https://example.com/jellyseerr

        This option requires rebuilding the jellyseerr package with the basePath
        baked in at build time, as Next.js does not support runtime basePath changes.

        When nginx is enabled, defaults to "/jellyseerr" for reverse proxy subpath access.
        Otherwise defaults to "" (root path).

        Note: Changing this option will trigger a full rebuild of the jellyseerr package.
      '';
      example = "/requests";
    };

    apiKey = secrets.mkSecretOption {
      default = null;
      description = "API key for Jellyseerr.";
    };

    externalBaseUrl = mkOption {
      type = types.str;
      default = "";
      example = "https://some.domain.com";
      description = ''
        Public accessible domain used for your services.
        This makes sure linking works when services link to each other.
      '';
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

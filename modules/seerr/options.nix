{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  syncMode = import ../../lib/sync-mode.nix { inherit lib pkgs; };
in
{
  options.nixflix.seerr = {
    enable = mkEnableOption "Seerr media request manager";

    package = mkPackageOption pkgs "seerr" { };

    apiKey = secrets.mkSecretOption {
      description = ''
        API key for Seerr. Can be created with:

        ```bash
        uuidgen | base64
        ```
      '';
    };

    externalUrlScheme = mkOption {
      type = types.nullOr types.str;
      default = null;
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
      description = "Subdomain prefix for reverse proxy.";
    };

    reverseProxy = {
      expose = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to expose Seerr via the reverse proxy.";
      };
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

      namespace = mkOption {
        type = types.str;
        default = config.nixflix.vpn.namespace;
        defaultText = literalExpression "config.nixflix.vpn.namespace";
        description = "Name of the VPN network namespace to confine Seerr to when `vpn.enable = true`.";
      };
    };

    syncMode = {
      radarr = syncMode.mkModeOption {
        inherit config;
        what = "Radarr servers";
        collectionOption = "nixflix.seerr.radarr";
      };

      sonarr = syncMode.mkModeOption {
        inherit config;
        what = "Sonarr servers";
        collectionOption = "nixflix.seerr.sonarr";
      };

      notifications =
        syncMode.mkModeOption {
          inherit config;
          what = "enabled Seerr notification agents";
          collectionOption = "nixflix.notif.<connector>.seerr";
        }
        // {
          description = ''
            What `seerr-notifications` does with Seerr notification agents
            (discord, email, ntfy, ...) that are enabled in Seerr but not
            targeted by any `nixflix.notif.<connector>.seerr` block. Agents are
            disabled rather than deleted. Defaults to `nixflix.syncMode`
            (`"delete"` unless set); setting this overrides it for these agents
            only.

            ${syncMode.modesDescription}
          '';
        };

      jellyfinLibraries =
        syncMode.mkModeOption {
          inherit config;
          what = "enabled Jellyfin libraries";
          collectionOption = "nixflix.seerr.jellyfin.libraryFilter";
        }
        // {
          description = ''
            What to do with Jellyfin libraries that are enabled in Seerr but do
            not match `nixflix.seerr.jellyfin.libraryFilter`. Seerr libraries are
            disabled rather than deleted, and only when
            `nixflix.seerr.jellyfin.enableAllLibraries = false`. Defaults to
            `nixflix.syncMode`.

            - `"delete"`: disable them.
            - `"keep"`: enable the matching libraries, leave the others as they
              are; the unit logs what it kept enabled.
            - `"refuse"`: if any would be disabled, fail the unit before changing
              anything and list them.
          '';
        };
    };

    connectionAddress = mkOption {
      type = types.str;
      readOnly = true;
      default =
        if config.nixflix.vpn.enable && config.nixflix.seerr.vpn.enable then
          config.vpnNamespaces.${config.nixflix.seerr.vpn.namespace}.namespaceAddress
        else
          "127.0.0.1";
      description = "Address for connecting to this service.";
    };
  };

  config = {
    assertions = [
      {
        assertion = config.nixflix.seerr.vpn.enable -> config.nixflix.vpn.enable;
        message = "Cannot enable VPN routing for Seerr (nixflix.seerr.vpn.enable = true) when VPN is not enabled. Please set nixflix.vpn.enable = true.";
      }
    ];

    warnings =
      lib.optional (config.nixflix.seerr.externalUrlScheme != null)
        "nixflix.seerr.externalUrlScheme is deprecated; it does not need to be set; It will be removed in a future version.";
  };
}

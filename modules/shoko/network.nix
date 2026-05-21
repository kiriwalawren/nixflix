{ config, lib, ... }:
let
  inherit (import ../../lib/mkVirtualHosts.nix { inherit lib config; }) mkVirtualHost;

  cfg = config.nixflix.shoko;
  hostname = "${cfg.subdomain}.${config.nixflix.reverseProxy.domain}";
in
with lib;
{
  options.nixflix.shoko = {
    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Open ports in the firewall for the ShokoAnime api and web interface.
      '';
    };

    port = mkOption {
      type = types.port;
      readOnly = true;
      internal = true;
      default = 8111;
    };

    subdomain = mkOption {
      type = types.str;
      default = "shoko";
      description = "Subdomain prefix for reverse proxy.";
    };

    reverseProxy = {
      expose = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to expose Shoko via the reverse proxy.";
      };
    };

    vpn = {
      enable = mkOption {
        type = types.bool;
        default = false;
        defaultText = literalExpression "config.nixflix.vpn.enable";
        description = ''
          Whether to route Shoko traffic through the VPN.

          When `false`, Shoko bypasses the VPN.
          When `true`, Shoko is confined to the WireGuard network namespace (requires nixflix.vpn.enable = true).
        '';
      };
    };

    connectionAddress = mkOption {
      type = types.str;
      readOnly = true;
      default =
        if config.nixflix.vpn.enable && cfg.vpn.enable then
          config.vpnNamespaces.wg.namespaceAddress
        else
          "127.0.0.1";
      description = "Address for connecting to this service.";
    };
  };

  config = mkIf (config.nixflix.enable && cfg.enable) (mkMerge [
    (mkVirtualHost {
      inherit hostname;
      inherit (cfg.reverseProxy) expose;
      inherit (cfg) port;
      upstreamHost =
        if config.nixflix.vpn.enable && cfg.vpn.enable then
          config.vpnNamespaces.wg.namespaceAddress
        else
          "127.0.0.1";
      disableBuffering = true;
      websocketUpgrade = true;
    })
    {
      networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];

      assertions = [
        {
          assertion = cfg.vpn.enable -> config.nixflix.vpn.enable;
          message = "Cannot enable VPN routing for Shoko (nixflix.shoko.vpn.enable = true) when VPN is not enabled. Please set nixflix.vpn.enable = true.";
        }
      ];
    }
    (mkIf (config.nixflix.vpn.enable && cfg.vpn.enable) {
      systemd.services.shoko.vpnConfinement = {
        enable = true;
        vpnNamespace = "wg";
      };
      vpnNamespaces.wg.portMappings = [
        {
          from = cfg.port;
          to = cfg.port;
          protocol = "tcp";
        }
      ];
    })
  ]);
}

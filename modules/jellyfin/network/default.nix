{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  inherit (config) nixflix;
  inherit (import ../../../lib/mkVirtualHosts.nix { inherit lib config; }) mkVirtualHost;
  cfg = config.nixflix.jellyfin;
  hostname = "${cfg.subdomain}.${nixflix.reverseProxy.domain}";

  xml = import ./xml.nix { inherit lib; };

  networkXmlContent = xml.mkXmlContent "NetworkConfiguration" cfg.network;
in
{
  imports = [ ./options.nix ];

  config = mkIf (nixflix.enable && cfg.enable) (mkMerge [
    (mkVirtualHost {
      inherit hostname;
      inherit (cfg.reverseProxy) expose;
      port = cfg.network.internalHttpPort;
      upstreamHost =
        if config.nixflix.vpn.enable && cfg.vpn.enable then
          config.vpnNamespaces.wg.namespaceAddress
        else
          "127.0.0.1";
      disableBuffering = true;
      websocketUpgrade = true;
    })
    {
      environment.etc = {
        "jellyfin/network.xml.template".text = networkXmlContent;
      };

      systemd.services.jellyfin = {
        restartTriggers = [
          networkXmlContent
        ];

        serviceConfig = {
          ExecStartPre = pkgs.writeShellScript "jellyfin-setup-config" ''
            set -eu

            ${pkgs.coreutils}/bin/install -m 640 /etc/jellyfin/network.xml.template '${cfg.configDir}/network.xml'
          '';
        };
      };

      networking.firewall = mkIf cfg.openFirewall {
        allowedTCPPorts = [
          cfg.network.internalHttpPort
          cfg.network.internalHttpsPort
        ];
        allowedUDPPorts = [
          1900
          7359
        ];
      };

    }
    (mkIf (config.nixflix.vpn.enable && cfg.vpn.enable) {
      systemd.services.jellyfin.vpnConfinement = {
        enable = true;
        vpnNamespace = "wg";
      };
      vpnNamespaces.wg.portMappings = [
        {
          from = cfg.network.internalHttpPort;
          to = cfg.network.internalHttpPort;
          protocol = "tcp";
        }
      ];
    })
  ]);
}

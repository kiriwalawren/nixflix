{ config, lib, ... }:
with lib;
let
  cfg = config.nixflix.vpn;
in
{
  options.nixflix.vpn = {
    enable = mkEnableOption ''
      WireGuard VPN. Configures Wireguard in a network namespace named `wg`.
      This is independent of the host network namespace. The host network remains untouched.
      This means that you can run another VPN client (Wireguard, Mullvad CLI, Tailscale, etc) on the host
      if you wish and both VPNs will work independently.

      When enabled, most Nixflix services can also be added to the VPN vpnConfinement
      with `nixflix.<service>.vpn.enable = true;`.

      !!! warning "Port forwarding is your responsibility"

          Enabling the VPN also confines qBittorrent and slskd to it by default
          (`nixflix.torrentClients.qbittorrent.vpn.enable` and `nixflix.slskd.vpn.enable`).
          Any port forwarding you have configured on your router (WAN) no longer reaches
          services inside the VPN, because incoming connections now arrive through the
          VPN tunnel instead.

          To restore incoming connections, you must use a VPN provider that supports port
          forwarding and configure it yourself. Nixflix does not manage this for you.
          For an example of how to automate this with ProtonVPN, see the
          [VPN Port Forwarding example](../../examples/vpn-port-forwarding.md).

      Any systemd service can be added to the VPN confinement manually with the following code:

      ```nix
      systemd.services.<serviceName>.vpnConfinement = {
        enable = true;
        vpnNamespace = "wg";
      };
      vpnNamespaces.wg.portMappings = [
        {
          from = <servicePort>;
          to = <servicePort>;
          protocol = "tcp";
        }
      ];
      ```
    '';

    namespace = mkOption {
      type = types.str;
      default = "wg";
      description = ''
        Name of the network namespace this VPN is configured in.

        Nixflix services confined to the VPN (via `nixflix.<service>.vpn.enable = true`)
        default to this namespace.
      '';
    };

    wgConfFile = mkOption {
      type = types.path;
      example = "/etc/wireguard/airvpn.conf";
      description = ''
        Path to a wg-quick compatible WireGuard configuration file.

        The file must contain at least `[Interface]` with `Address`, `PrivateKey`,
        and `DNS` fields, and one or more `[Peer]` sections with `PublicKey`,
        `Endpoint`, and `AllowedIPs`.

        This file is read at service startup. Use a path to a file managed by
        your secrets solution (e.g. agenix, sops-nix) to keep the private key
        out of the Nix store.
      '';
    };

    accessibleFrom = mkOption {
      type = types.listOf types.str;
      default = [ "192.168.1.0/24" ];
      example = [ "192.168.1.0/24" ];
      description = ''
        List of subnets or addresses in the default network namespace that
        should be able to reach services confined in the VPN namespace.

        Required to access VPN-confined services (e.g. Radarr, Sonarr) from
        your local network. Example: `["192.168.1.0/24"]`.
      '';
    };

    allowedEgress = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "192.168.1.10" ];
      description = ''
        Subnets or addresses outside the VPN tunnel that VPN-confined services
        may open connections to, such as an external PostgreSQL server set in
        `nixflix.postgres.host`. All other outgoing traffic still goes through
        the tunnel.
      '';
    };

    openVPNPorts = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            port = mkOption {
              type = types.port;
              description = "Port number to open through the VPN interface.";
            };
            protocol = mkOption {
              type = types.enum [
                "tcp"
                "udp"
                "both"
              ];
              default = "tcp";
              description = "Protocol for the port.";
            };
          };
        }
      );
      default = [ ];
      example = [
        {
          port = 60729;
          protocol = "both";
        }
      ];
      description = ''
        Ports to open through the VPN interface, e.g. for port forwarding
        provided by the VPN provider (AirVPN, IVPN, etc.).
      '';
    };

  };

  config = mkIf cfg.enable {
    vpnNamespaces.${cfg.namespace} = {
      enable = true;
      wireguardConfigFile = cfg.wgConfFile;
      inherit (cfg) accessibleFrom allowedEgress;
      inherit (cfg) openVPNPorts;
    };
  };
}

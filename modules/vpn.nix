{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.nixflix.vpn;
in
{
  options.nixflix.vpn = {
    enable = mkEnableOption "WireGuard VPN";

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

    tailscale = {
      enable = mkOption {
        type = types.bool;
        default = config.services.tailscale.enable;
        defaultText = literalExpression "config.services.tailscale.enable";
        description = ''
          Automatically configure Tailscale to coexist with the VPN.

          Adds nftables rules to bypass the VPN for Tailscale mesh traffic
          (100.64.0.0/10) and the Tailscale WireGuard port (UDP 41641).
        '';
      };

      exitNode = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Route Tailscale exit node traffic through the VPN.

          When false (default), all Tailscale traffic bypasses the VPN entirely.

          When true, direct mesh traffic and Tailscale protocol traffic still bypass
          the VPN, but exit node traffic is routed through the VPN tunnel.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    vpnNamespaces.wg = {
      enable = true;
      wireguardConfigFile = cfg.wgConfFile;
      inherit (cfg) accessibleFrom;
      inherit (cfg) openVPNPorts;
    };

    networking.nftables.enable = mkIf cfg.tailscale.enable true;

    networking.nftables.tables."wg-tailscale" = mkIf cfg.tailscale.enable {
      enable = true;
      family = "inet";
      content =
        if cfg.tailscale.exitNode then
          ''
            chain prerouting {
              type filter hook prerouting priority -50; policy accept;

              # Allow Tailscale protocol traffic to bypass WireGuard
              udp dport 41641 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;

              # Allow direct mesh traffic (Tailscale device to Tailscale device) to bypass WireGuard
              ip saddr 100.64.0.0/10 ip daddr 100.64.0.0/10 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;

              # Exit node traffic: DON'T mark it - let it route through VPN without bypass mark
              iifname "tailscale0" ip daddr != 100.64.0.0/10 meta mark set 0;

              # Return traffic from VPN: Mark it so it routes via Tailscale table
              iifname "wg0" ip daddr 100.64.0.0/10 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
            }

            chain outgoing {
              type route hook output priority -100; policy accept;
              meta mark 0x80000 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
              ip daddr 100.64.0.0/10 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
              udp sport 41641 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
              ct state new meta mark == 0x6d6f6c65 ct mark set 0x00000f41;
            }

            chain postrouting {
              type nat hook postrouting priority 100; policy accept;

              # Masquerade exit node traffic going through WireGuard
              iifname "tailscale0" oifname "wg0" masquerade;
            }
          ''
        else
          ''
            chain prerouting {
              type filter hook prerouting priority -100; policy accept;
              ip saddr 100.64.0.0/10 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
              udp dport 41641 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
            }

            chain outgoing {
              type route hook output priority -100; policy accept;
              meta mark 0x80000 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
              ip daddr 100.64.0.0/10 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
              udp sport 41641 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
              ct state new meta mark == 0x6d6f6c65 ct mark set 0x00000f41;
            }
          '';
    };
  };
}

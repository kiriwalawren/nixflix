{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.nixflix.vpn.wireguard;
  vpnCfg = config.nixflix.vpn;
in
{
  options.nixflix.vpn.wireguard = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether to enable generic WireGuard VPN.

        Accepts any WireGuard provider's wg-quick configuration file.
        Compatible with AirVPN, ProtonVPN, IVPN, Mullvad (wireguard mode),
        and any other provider that issues wg-quick `.conf` files.

        Services with `vpn.enable = true` are confined to a network namespace
        that routes all traffic through the WireGuard tunnel. Services with
        `vpn.enable = false` run normally and bypass the tunnel.

        #### Using Tailscale with WireGuard

        When `services.tailscale.enable` is true, nftables rules are automatically
        configured to route Tailscale traffic around the VPN tunnel. To disable
        this behaviour, set `nixflix.vpn.tailscale.enable = false`.
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
      default = [ ];
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
  };

  config = mkIf cfg.enable {
    vpnNamespaces.wg = {
      enable = true;
      wireguardConfigFile = cfg.wgConfFile;
      inherit (cfg) accessibleFrom;
      inherit (cfg) openVPNPorts;
    };

    networking.nftables.enable = mkIf vpnCfg.tailscale.enable true;

    networking.nftables.tables."wg-tailscale" = mkIf vpnCfg.tailscale.enable {
      enable = true;
      family = "inet";
      content =
        if vpnCfg.tailscale.exitNode then
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

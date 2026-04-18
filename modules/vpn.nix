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

  };

  config = mkIf cfg.enable {
    vpnNamespaces.wg = {
      enable = true;
      wireguardConfigFile = cfg.wgConfFile;
      inherit (cfg) accessibleFrom;
      inherit (cfg) openVPNPorts;
    };
  };
}

{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix.vpn;
in
{
  imports = [
    ./mullvad.nix
    ./wireguard.nix
  ];

  options.nixflix.vpn = {
    enable = mkOption {
      type = types.bool;
      readOnly = true;
      default = cfg.mullvad.enable || cfg.wireguard.enable;
      description = "True if any VPN provider is enabled. Derived from mullvad.enable or wireguard.enable.";
    };

    dns = mkOption {
      type = types.listOf types.str;
      default = [
        "1.1.1.1"
        "1.0.0.1"
        "8.8.8.8"
        "8.8.4.4"
      ];
      defaultText = literalExpression ''["1.1.1.1" "1.0.0.1" "8.8.8.8" "8.8.4.4"]'';
      example = [
        "194.242.2.4"
        "194.242.2.3"
      ];
      description = ''
        DNS servers to use with the VPN.
        Defaults to Cloudflare (1.1.1.1, 1.0.0.1) and Google (8.8.8.8, 8.8.4.4) DNS servers.
      '';
    };

    killSwitch = {
      enable = mkEnableOption "VPN kill switch - blocks all traffic when VPN is down";

      allowLan = mkOption {
        type = types.bool;
        default = true;
        description = "Allow LAN traffic when VPN is down (only effective with kill switch enabled)";
      };
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

    vpnWrapper = mkOption {
      type = types.package;
      readOnly = true;
      default = pkgs.writeShellScriptBin "vpn-exec" ''exec "$@"'';
      description = ''
        Wrapper derivation applied when a service routes through the VPN (service vpn.enable = true).
        - WireGuard: no-op — confinement is handled via systemd vpnConfinement (NetworkNamespacePath).
        - Mullvad: no-op (Mullvad daemon handles routing for all processes by default).
      '';
    };

    bypassWrapper = mkOption {
      type = types.package;
      readOnly = true;
      default =
        if cfg.mullvad.enable then
          pkgs.writeShellScriptBin "vpn-bypass" ''
            exec /run/wrappers/bin/mullvad-exclude "$@"
          ''
        else
          pkgs.writeShellScriptBin "vpn-bypass" ''exec "$@"'';
      description = ''
        Wrapper derivation applied when a service bypasses the VPN (service vpn.enable = false).
        - Mullvad: wraps the process with mullvad-exclude to bypass the VPN tunnel.
        - WireGuard: no-op (processes run normally outside the wg network namespace).
      '';
    };
  };

  config = {
    assertions = [
      {
        assertion = !(cfg.mullvad.enable && cfg.wireguard.enable);
        message = "nixflix.vpn: cannot enable both nixflix.vpn.mullvad and nixflix.vpn.wireguard simultaneously.";
      }
    ];
  };
}

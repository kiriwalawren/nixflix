{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  secrets = import ./lib/secrets { inherit lib; };
  cfg = config.nixflix.mullvad;
  mullvadPkg = if cfg.gui.enable then pkgs.mullvad-vpn else pkgs.mullvad;
in
{
  options.nixflix.mullvad = {
    enable = mkOption {
      default = false;
      example = true;
      description = ''
        Whether to enable Mullvad VPN.

        #### Using Tailscale with Mullvad

        If you want to use Tailscale alongside Mullvad VPN, you'll need to configure nftables rules to route Tailscale traffic around the VPN. Add this to your NixOS configuration:

        ```nix
        {
          networking.nftables = {
            enable = true;
            tables."mullvad-tailscale" = {
              family = "inet";
              content = '''
                chain prerouting {
                  type filter hook prerouting priority -100; policy accept;
                  ip saddr 100.64.0.0/10 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
                  udp dport 41641 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
                  # Allow incoming UDP on Tailscale port to bypass Mullvad
                  udp dport 41641 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
                }

                chain outgoing {
                  type route hook output priority -100; policy accept;
                  meta mark 0x80000 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
                  ip daddr 100.64.0.0/10 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
                  # Allow outgoing UDP from Tailscale port to bypass Mullvad
                  udp sport 41641 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
                }
              ''';
            };
          };
        }
        ```

        This ensures Tailscale traffic (100.64.0.0/10) bypasses the Mullvad VPN tunnel.

        If you want tailscale exit node traffic to be routed through mullvad instead of
        the server's own established internet connection, then you need the following:

        ```nix
        networking.nftables = {
          enable = true;
          tables."mullvad-tailscale" = {
            family = "inet";
            content = '''
              chain prerouting {
                type filter hook prerouting priority -50; policy accept;

                # Allow Tailscale protocol traffic to bypass Mullvad
                udp dport 41641 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;

                # Allow direct mesh traffic (Tailscale device to Tailscale device) to bypass Mullvad
                ip saddr 100.64.0.0/10 ip daddr 100.64.0.0/10 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;

                # Exit node traffic: DON'T mark it - let it route through VPN without bypass mark
                # Clear meta mark so it routes through Mullvad (no ct mark means Mullvad won't drop in NAT)
                iifname "tailscale0" ip daddr != 100.64.0.0/10 meta mark set 0;

                # Return traffic from VPN: Mark it so it routes via Tailscale table
                # Use bypass mark so it doesn't get routed back through Mullvad
                iifname "wg0-mullvad" ip daddr 100.64.0.0/10 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
              }

              chain outgoing {
                type route hook output priority -100; policy accept;
                meta mark 0x80000 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
                ip daddr 100.64.0.0/10 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
                # Allow outgoing UDP from Tailscale port to bypass Mullvad
                udp sport 41641 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
              }

              chain postrouting {
                type nat hook postrouting priority 100; policy accept;

                # Masquerade exit node traffic going through Mullvad
                iifname "tailscale0" oifname "wg0-mullvad" masquerade;
              }
            ''';
          };
        };
        ```
      '';
      type = types.bool;
    };

    accountNumber = secrets.mkSecretOption {
      default = null;
      description = "Mullvad account number.";
    };

    gui = {
      enable = mkEnableOption "Mullvad GUI application";
    };

    location = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "us"
        "nyc"
      ];
      description = ''
        Mullvad server location as a list of strings.

        Format: `["country"]` | `["country" "city"]` | `["country" "city" "full-server-name"]` | `["full-server-name"]`

        Examples: `["us"]`, `["us" "nyc"]`, `["se" "got" "se-got-wg-001"]`, `["se-got-wg-001"]`

        Use "mullvad relay list" to see available locations.
        Leave empty to use automatic location selection.
      '';
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

    autoConnect = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically connect to VPN on startup";
    };

    killSwitch = {
      enable = mkEnableOption "VPN kill switch (lockdown mode) - blocks all traffic when VPN is down";

      allowLan = mkOption {
        type = types.bool;
        default = true;
        description = "Allow LAN traffic when VPN is down (only effective with kill switch enabled)";
      };
    };
  };

  config = mkIf cfg.enable {
    services.resolved.enable = true;

    services.mullvad-vpn = {
      enable = true;
      enableExcludeWrapper = true;
      package = mullvadPkg;
    };

    systemd.services.mullvad-config = {
      description = "Configure Mullvad VPN settings";
      wantedBy = [ "multi-user.target" ];
      after = [
        "mullvad-daemon.service"
        "network-online.target"
      ];
      requires = [
        "mullvad-daemon.service"
        "network-online.target"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "configure-mullvad" ''
          for i in {1..30}; do
            if ${mullvadPkg}/bin/mullvad status &>/dev/null; then
              echo "Mullvad daemon is ready with relay list available"
              sleep 2
              break
            fi
            sleep 1
          done

          ${optionalString (cfg.accountNumber != null) ''
            if ${mullvadPkg}/bin/mullvad account get | grep -q "Not logged in"; then
              echo "Logging in to Mullvad account..."
              echo "${secrets.toShellValue cfg.accountNumber}" | ${mullvadPkg}/bin/mullvad account login

              echo "Waiting for relay list to download..."
              for i in {1..30}; do
                RELAY_COUNT=$(${mullvadPkg}/bin/mullvad relay list 2>/dev/null | wc -l)
                if [ "$RELAY_COUNT" -gt 10 ]; then
                  echo "Relay list populated ($RELAY_COUNT lines)"
                  sleep 1
                  break
                fi
                sleep 1
              done
            fi
          ''}

          ${mullvadPkg}/bin/mullvad dns set custom ${concatStringsSep " " cfg.dns}

          ${optionalString (cfg.location != [ ]) ''
            ${mullvadPkg}/bin/mullvad relay set location ${escapeShellArgs cfg.location}
          ''}

          ${optionalString cfg.killSwitch.enable ''
            ${mullvadPkg}/bin/mullvad lockdown-mode set on
            ${mullvadPkg}/bin/mullvad lan set ${if cfg.killSwitch.allowLan then "allow" else "block"}
          ''}

          ${optionalString (!cfg.killSwitch.enable) ''
            ${mullvadPkg}/bin/mullvad lockdown-mode set off
          ''}

          ${optionalString cfg.autoConnect ''
            ${mullvadPkg}/bin/mullvad auto-connect set on
            ${mullvadPkg}/bin/mullvad connect
          ''}

          ${optionalString (!cfg.autoConnect) ''
            ${mullvadPkg}/bin/mullvad auto-connect set off
          ''}
        '';
        ExecStop = pkgs.writeShellScript "logout-mullvad" ''
          DEVICE_NAME=$(${mullvadPkg}/bin/mullvad account get | grep "Device name:" | sed 's/.*Device name:[[:space:]]*//')
          if [ -n "$DEVICE_NAME" ]; then
            echo "Revoking device: $DEVICE_NAME"
            ${mullvadPkg}/bin/mullvad account revoke-device "$DEVICE_NAME" || true
          fi
          ${mullvadPkg}/bin/mullvad account logout  || true
          ${mullvadPkg}/bin/mullvad disconnect || true
        '';
      };
    };
  };
}

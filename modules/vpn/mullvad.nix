{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  cfg = config.nixflix.vpn.mullvad;
  vpnCfg = config.nixflix.vpn;
  mullvadPkg = if cfg.gui.enable then pkgs.mullvad-vpn else pkgs.mullvad;
in
{
  options.nixflix.vpn.mullvad = {
    enable = mkOption {
      default = false;
      example = true;
      description = ''
        Whether to enable Mullvad VPN.

        #### Using Tailscale with Mullvad

        When `services.tailscale.enable` is true, nftables rules are automatically
        configured to route Tailscale traffic around the VPN tunnel. To disable
        this behaviour, set `nixflix.vpn.tailscale.enable = false`.

        By default, all Tailscale traffic (mesh and exit node) bypasses Mullvad.
        To route exit node traffic through Mullvad while keeping mesh traffic
        direct, set `nixflix.vpn.tailscale.exitNode = true`.
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

    enableIPv6 = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to enable IPv6 for Mullvad";
    };

    autoConnect = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically connect to VPN on startup";
    };

    persistDevice = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Keep the Mullvad device logged in across service restarts and reboots.

        When false (default), the service logs out and revokes the device on stop,
        requiring a fresh login on next start. This frees up device slots (Mullvad
        allows 5 devices per account).

        When true, the service only disconnects on stop without logging out.
      '';
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

          ${mullvadPkg}/bin/mullvad dns set custom ${concatStringsSep " " vpnCfg.dns}

          ${mullvadPkg}/bin/mullvad tunnel set ipv6 ${if cfg.enableIPv6 then "on" else "off"}

          ${optionalString (cfg.location != [ ]) ''
            ${mullvadPkg}/bin/mullvad relay set location ${escapeShellArgs cfg.location}
          ''}

          ${optionalString vpnCfg.killSwitch.enable ''
            ${mullvadPkg}/bin/mullvad lockdown-mode set on
            ${mullvadPkg}/bin/mullvad lan set ${if vpnCfg.killSwitch.allowLan then "allow" else "block"}
          ''}

          ${optionalString (!vpnCfg.killSwitch.enable) ''
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
        ExecStop =
          if cfg.persistDevice then
            pkgs.writeShellScript "disconnect-mullvad" ''
              ${mullvadPkg}/bin/mullvad disconnect || true
            ''
          else
            pkgs.writeShellScript "logout-mullvad" ''
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

    networking.nftables.enable = mkIf vpnCfg.tailscale.enable true;

    networking.nftables.tables."mullvad-tailscale" = mkIf vpnCfg.tailscale.enable {
      enable = true;
      family = "inet";
      content =
        if vpnCfg.tailscale.exitNode then
          ''
            chain prerouting {
              type filter hook prerouting priority -50; policy accept;

              # Allow Tailscale protocol traffic to bypass Mullvad
              udp dport 41641 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;

              # Allow direct mesh traffic (Tailscale device to Tailscale device) to bypass Mullvad
              ip saddr 100.64.0.0/10 ip daddr 100.64.0.0/10 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;

              # Exit node traffic: DON'T mark it - let it route through VPN without bypass mark
              iifname "tailscale0" ip daddr != 100.64.0.0/10 meta mark set 0;

              # Return traffic from VPN: Mark it so it routes via Tailscale table
              iifname "wg0-mullvad" ip daddr 100.64.0.0/10 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
            }

            chain outgoing {
              type route hook output priority -100; policy accept;
              meta mark 0x80000 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
              ip daddr 100.64.0.0/10 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
              udp sport 41641 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;

              # Fix Tailscale 1.96+ connmark interference with mullvad-exclude:
              # Tailscale's mangle/OUTPUT rule (priority -150) saves bits 16-23 of the
              # meta mark into the ct mark for every new connection. The Mullvad bypass
              # mark 0x6d6f6c65 has those bits set (& 0xff0000 = 0x6f0000), so Tailscale
              # saves 0x006f0000 into the ct mark. Its mangle/PREROUTING rule then
              # restores 0x006f0000 as the meta mark on incoming replies, which no longer
              # equals the full bypass mark 0x6d6f6c65 and is dropped by Mullvad's
              # INPUT firewall. Setting ct mark to 0x00000f41 here (whose bits 16-23 are
              # zero) prevents the PREROUTING restore from firing.
              ct state new meta mark == 0x6d6f6c65 ct mark set 0x00000f41;
            }

            chain postrouting {
              type nat hook postrouting priority 100; policy accept;

              # Masquerade exit node traffic going through Mullvad
              iifname "tailscale0" oifname "wg0-mullvad" masquerade;
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

              # Fix Tailscale 1.96+ connmark interference with mullvad-exclude (see exit-node chain above).
              ct state new meta mark == 0x6d6f6c65 ct mark set 0x00000f41;
            }
          '';
    };
  };
}

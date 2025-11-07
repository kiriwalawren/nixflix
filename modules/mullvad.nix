{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.nixflix.mullvad;
  mullvadPkg =
    if cfg.gui.enable
    then pkgs.mullvad-vpn
    else pkgs.mullvad;
in {
  options.nixflix.mullvad = {
    enable = mkEnableOption "Mullvad VPN";

    accountNumberPath = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing the Mullvad account number";
    };

    gui = {
      enable = mkEnableOption "Mullvad GUI application";
    };

    location = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["us" "nyc"];
      description = ''
        Mullvad server location as a list of strings.
        Format: ["country"] | ["country" "city"] | ["country" "city" "full-server-name"] | ["full-server-name"]
        Examples: ["us"], ["us" "nyc"], ["se" "got" "se-got-wg-001"], ["se-got-wg-001"]
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
      example = ["194.242.2.4" "194.242.2.3"];
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
      wantedBy = ["multi-user.target"];
      after = ["mullvad-daemon.service" "network-online.target"];
      requires = ["mullvad-daemon.service" "network-online.target"];
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

          ${optionalString (cfg.accountNumberPath != null) ''
            if ${mullvadPkg}/bin/mullvad account get | grep -q "Not logged in"; then
              echo "Logging in to Mullvad account..."
              ACCOUNT_NUMBER=$(cat ${cfg.accountNumberPath})
              ${mullvadPkg}/bin/mullvad account login "$ACCOUNT_NUMBER"

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

          ${optionalString (cfg.location != []) ''
            ${mullvadPkg}/bin/mullvad relay set location ${escapeShellArgs cfg.location}
          ''}

          ${optionalString cfg.killSwitch.enable ''
            ${mullvadPkg}/bin/mullvad lockdown-mode set on
            ${mullvadPkg}/bin/mullvad lan set ${
              if cfg.killSwitch.allowLan
              then "allow"
              else "block"
            }
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

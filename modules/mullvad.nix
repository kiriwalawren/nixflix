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
      type = types.str;
      default = "";
      example = "us nyc";
      description = ''
        Mullvad server location as a space-separated string.
        Format: "country city" or "country" (e.g., "us nyc", "se got", "us").
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
      enableExcludeWrapper = false;
      package = mullvadPkg;
    };

    systemd.services.mullvad-config = {
      description = "Configure Mullvad VPN settings";
      wantedBy = ["multi-user.target"];
      wants = ["mullvad-daemon.service" "network-online.target"];
      after = ["mullvad-daemon.service" "network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "configure-mullvad" ''
          for i in {1..30}; do
            if ${mullvadPkg}/bin/mullvad status &>/dev/null; then
              break
            fi
            sleep 1
          done

          ${optionalString (cfg.accountNumberPath != null) ''
            if ${mullvadPkg}/bin/mullvad account get | grep -q "Not logged in"; then
              echo "Logging in to Mullvad account..."
              ACCOUNT_NUMBER=$(cat ${cfg.accountNumberPath})
              ${mullvadPkg}/bin/mullvad account login "$ACCOUNT_NUMBER"
            fi
          ''}

          ${mullvadPkg}/bin/mullvad dns set custom ${concatStringsSep " " cfg.dns}

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

          ${optionalString (cfg.location != "") ''
            ${mullvadPkg}/bin/mullvad relay set location ${cfg.location}
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
          ${mullvadPkg}/bin/mullvad disconnect || true
          ${mullvadPkg}/bin/mullvad account logout || true
        '';
      };
    };
  };
}

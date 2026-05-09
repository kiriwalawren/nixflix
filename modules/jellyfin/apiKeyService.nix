{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  inherit (config) nixflix;
  cfg = config.nixflix.jellyfin;

  waitForApiScript = import ./waitForApiScript.nix {
    inherit pkgs;
    jellyfinCfg = cfg;
  };
in
{
  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.services.jellyfin-api-key = {
      description = "Inject Jellyfin API key into database";
      after = [ "jellyfin.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        ExecStartPre = waitForApiScript;
        ExecStartPost = waitForApiScript;
      };

      path = [
        pkgs.sqlite
        pkgs.systemd
        pkgs.coreutils
      ];

      script = ''
        set -eu

        DB="${cfg.dataDir}/data/jellyfin.db"
        API_KEY=${secrets.toShellValue cfg.apiKey}

        # Validate format: prevent SQL injection
        if ! [[ "$API_KEY" =~ ^[A-Za-z0-9_-]+$ ]]; then
          echo "Invalid API key format: must only contain alphanumeric characters, underscores, or hyphens" >&2
          exit 1
        fi

        # Check existing key in database
        EXISTING_KEY=$(sqlite3 "$DB" "SELECT AccessToken FROM ApiKeys WHERE Name='nixflix'" 2>/dev/null || echo "")

        if [ "$EXISTING_KEY" = "$API_KEY" ]; then
          echo "API key is already correct, no changes needed"
          exit 0
        fi

        echo "Updating Jellyfin API key..."

        # Must stop Jellyfin before writing to the database
        systemctl stop jellyfin.service

        sqlite3 "$DB" "BEGIN TRANSACTION; DELETE FROM ApiKeys WHERE Name='nixflix'; INSERT INTO ApiKeys (AccessToken, Name, DateCreated, DateLastActivity) VALUES ('$API_KEY', 'nixflix', datetime('now'), datetime('now')); COMMIT;"

        echo "API key injected successfully"

        systemctl start jellyfin.service
      '';
    };
  };
}

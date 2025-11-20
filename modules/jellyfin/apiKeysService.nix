{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  inherit (config) nixflix;
  cfg = config.nixflix.jellyfin;
in {
  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.services.jellyfin-api-keys = {
      description = "Jellyfin API Keys Initialization";
      after = ["jellyfin-initialization.service"];
      requires = ["jellyfin-initialization.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = let
        dbPath = "${cfg.dataDir}/data/jellyfin.db";
      in ''
        set -eu

        # Wait for database to be created by Jellyfin
        timeout=60
        elapsed=0
        while [ ! -f "${dbPath}" ] && [ $elapsed -lt $timeout ]; do
          echo "Waiting for Jellyfin database to be created..."
          sleep 2
          elapsed=$((elapsed + 2))
        done

        if [ ! -f "${dbPath}" ]; then
          echo "ERROR: Jellyfin database not found at ${dbPath} after $timeout seconds"
          exit 1
        fi

        # Create temporary file for SQL commands
        dbcmds=$(${pkgs.coreutils}/bin/mktemp)
        trap "${pkgs.coreutils}/bin/rm -f $dbcmds" EXIT

        echo "BEGIN TRANSACTION;" > "$dbcmds"

        ${concatStringsSep "\n" (
          mapAttrsToList (
            appName: keyPath: ''
              echo "REPLACE INTO ApiKeys (DateCreated, DateLastActivity, Name, AccessToken) VALUES(strftime('%Y-%m-%d %H:%M:%S', 'now'), strftime('%Y-%m-%d %H:%M:%S', 'now'), '${appName}', '$(${pkgs.coreutils}/bin/cat "${keyPath}")');" >> "$dbcmds"
            ''
          )
          cfg.apikeys
        )}

        echo "COMMIT;" >> "$dbcmds"

        # Execute SQL commands
        ${pkgs.sqlite}/bin/sqlite3 "${dbPath}" < "$dbcmds"

        echo "API keys initialized successfully"
      '';
    };
  };
}

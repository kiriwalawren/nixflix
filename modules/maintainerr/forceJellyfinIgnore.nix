{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix.maintainerr;

  mediaDirsToScan =
    optionals config.nixflix.sonarr.enable config.nixflix.sonarr.mediaDirs
    ++ optionals config.nixflix.sonarr-anime.enable config.nixflix.sonarr-anime.mediaDirs;

  videoExtensions = [
    "mkv"
    "mp4"
    "avi"
    "m4v"
    "mov"
    "wmv"
    "flv"
    "mpg"
    "mpeg"
    "webm"
    "ts"
    "m2ts"
  ];

  videoFindExpr = concatStringsSep " -o " (
    map (ext: "-iname ${escapeShellArg ("*." + ext)}") videoExtensions
  );

  mkScanMediaDirBlock = mediaDir: ''
    MEDIA_DIR=${escapeShellArg mediaDir}
    if [ ! -d "$MEDIA_DIR" ]; then
      echo "Warning: media directory $MEDIA_DIR does not exist, skipping." >&2
    else
      echo "Scanning $MEDIA_DIR for shows with no video files..."
      while IFS= read -r -d ''' SHOW_DIR; do
        [ -d "$SHOW_DIR" ] || continue
        if [ -n "$(${pkgs.findutils}/bin/find "$SHOW_DIR" -type f \( ${videoFindExpr} \) -print -quit)" ]; then
          if [ -e "$SHOW_DIR/.ignore" ]; then
            echo "  Video file(s) found, removing .ignore: $SHOW_DIR"
            rm -f "$SHOW_DIR/.ignore"
          fi
        else
          if [ ! -e "$SHOW_DIR/.ignore" ]; then
            echo "  No video files found, creating .ignore: $SHOW_DIR"
            touch "$SHOW_DIR/.ignore"
          fi
        fi
      done < <(${pkgs.findutils}/bin/find "$MEDIA_DIR" -mindepth 1 -maxdepth 1 -type d -print0)
    fi
  '';
in
{
  config =
    mkIf (config.nixflix.enable && cfg.enable && cfg.settings.forceJellyfinToIgnoreEmptyMediaFolders)
      {
        systemd.timers.maintainerr-jellyfin-ignore = {
          description = "Manage Jellyfin .ignore files for empty media folders";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "5min";
            OnUnitActiveSec = "30min";
            Unit = "maintainerr-jellyfin-ignore.service";
          };
        };

        systemd.services.maintainerr-jellyfin-ignore = {
          description = "Add and remove .ignore files for empty Jellyfin media folders";
          after = [ "nixflix-setup-dirs.service" ];
          requires = [ "nixflix-setup-dirs.service" ];

          serviceConfig = {
            Type = "oneshot";
            ProtectSystem = "strict";
            ProtectHome = true;
            ReadWritePaths = mediaDirsToScan;
            PrivateTmp = true;
            ExecStart = pkgs.writeShellScript "maintainerr-jellyfin-ignore" ''
              set -euo pipefail

              ${concatMapStrings mkScanMediaDirBlock mediaDirsToScan}

              echo "Jellyfin ignore file management complete."
            '';
          };
        };
      };
}
